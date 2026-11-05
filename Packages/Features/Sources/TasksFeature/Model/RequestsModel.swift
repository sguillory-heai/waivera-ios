import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// A pending approve or reject, confirmed on its own sheet before it is sent.
struct Decision: Hashable, Sendable {
    var item: RequestItem
    var approve: Bool
}

struct RequestsScreenState: Equatable, Sendable {
    var waiting: Loadable<[RequestItem]> = .loading
    var mine: Loadable<[RequestItem]> = .loading
    var reviewing: RequestItem?
    var confirming: Decision?
    var isRefreshing = false
    /// Time off under review: the balance, or nil when this reviewer may not see balances.
    var balance: Loadable<BalanceChange?> = .loading
    /// Training credit under review.
    var training: Loadable<TrainingCredit> = .loading
    /// What the reviewer writes on a training decision.
    var reason = ""
    /// The training certificate is downloading; another tap waits for it.
    var openingCertificate = false
    /// The downloaded certificate, shown in its own viewer.
    var certificate: DownloadedFile?

    /// Whether the confirm button can send: a training decision may need a written reason first.
    var canConfirm: Bool {
        guard let decision = confirming else { return false }
        guard decision.item.request.kind == .trainingCredit else { return true }
        guard let credit = training.value else { return false }
        let reasonNeeded = !decision.approve || credit.needsApproveReason
        return credit.decidable && (!reasonNeeded || !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }
}

/// The Requests segment (Android `RequestsViewModel`): requests waiting on this person, then
/// their own. Approve and reject are optimistic: the card leaves at once and comes back, with a
/// note, if the server says no.
@MainActor
@Observable
final class RequestsModel {
    static let webPath = "/admin-requests"
    static let reasonMaxLength = 2_000

    private(set) var state = RequestsScreenState()
    let feedback = TasksFeedback()

    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let bag = TaskBag()
    @ObservationIgnored private var waiting: [ChangeRequest]?
    @ObservationIgnored private var waitingFailed = false
    @ObservationIgnored private var mine: Loadable<[ChangeRequest]> = .loading
    @ObservationIgnored private var reviewingId: Int?
    @ObservationIgnored private var confirming: (id: Int, approve: Bool)?
    @ObservationIgnored private var isRefreshing = false
    @ObservationIgnored private var balance: Loadable<BalanceChange?> = .loading
    @ObservationIgnored private var training: Loadable<TrainingCredit> = .loading
    @ObservationIgnored private var reason = ""
    @ObservationIgnored private var openingCertificate = false
    @ObservationIgnored private var certificate: DownloadedFile?
    @ObservationIgnored private var leaveZone: TimeZone?
    @ObservationIgnored private var leaveZoneAsked = false
    @ObservationIgnored private var started = false

    init(environment: DataEnvironment) {
        self.environment = environment
        rebuild()
    }

    func run() async {
        if !started {
            started = true
            bag.run { [weak self] in await self?.load(refreshing: false) }
        }
        for await value in environment.requests.waiting() {
            waiting = value
            rebuild()
        }
    }

    func refresh() async { await load(refreshing: true) }

    func retryWaiting() { bag.run { [weak self] in await self?.load(refreshing: false) } }

    func retryMine() {
        mine = .loading
        rebuild()
        bag.run { [weak self] in await self?.loadMine() }
    }

    /// Kinds the phone does not review open on the web; `nil` means the review sheet opened.
    func review(_ item: RequestItem) -> URL? {
        guard item.request.kind.reviewableHere else { return webURL() }
        reviewingId = item.id
        reason = ""
        balance = .loading
        training = .loading
        rebuild()
        loadDetails(item.request)
        return nil
    }

    func retryDetails() {
        guard let request = state.reviewing?.request else { return }
        balance = .loading
        training = .loading
        rebuild()
        loadDetails(request)
    }

    func closeReview() {
        bag.cancel(Self.detailsKey)
        bag.cancel(Self.certificateKey)
        reviewingId = nil
        confirming = nil
        reason = ""
        openingCertificate = false
        certificate = nil
        rebuild()
    }

    func ask(approve: Bool) {
        guard let id = reviewingId else { return }
        reason = ""
        confirming = (id, approve)
        rebuild()
    }

    func setReason(_ text: String) {
        reason = String(text.prefix(Self.reasonMaxLength))
        rebuild()
    }

    /// Downloads the certificate once and shows it; repeat taps wait for it.
    func openCertificate() {
        guard let request = state.reviewing?.request, !openingCertificate else { return }
        openingCertificate = true
        rebuild()
        let requests = environment.requests
        bag.replace(Self.certificateKey) { [weak self] in
            let file = try? await requests.trainingCertificate(requestId: request.id)
            guard let self, !Task.isCancelled else { return }
            self.openingCertificate = false
            if let file {
                self.certificate = file
            } else {
                self.feedback.show(TasksStrings.text("tasks.review.certificateFailed"))
            }
            self.rebuild()
        }
    }

    func closeCertificate() {
        certificate = nil
        rebuild()
    }

    func cancelConfirm() {
        confirming = nil
        rebuild()
    }

    /// Sends the confirmed decision. Both sheets close at once; the list already shows the result.
    func confirm() {
        guard let decision = state.confirming, state.canConfirm else { return }
        let training: TrainingDecision? =
            if decision.item.request.kind == .trainingCredit, let revision = state.training.value?.revision {
                TrainingDecision(revision: revision, reason: reason.trimmingCharacters(in: .whitespacesAndNewlines))
            } else {
                nil
            }
        reviewingId = nil
        confirming = nil
        reason = ""
        rebuild()
        let requests = environment.requests
        bag.run { [weak self] in
            do {
                try await requests.decide(decision.item.request, approve: decision.approve, training: training)
                let who = decision.item.request.requesterName
                self?.feedback.show(
                    TasksStrings.format(decision.approve ? "tasks.decided.approved" : "tasks.decided.rejected", who)
                )
                await self?.loadMine()
            } catch {
                if WaiveraError.from(error) == .notFound {
                    self?.feedback.show(TasksStrings.text("tasks.alreadyDecided"))
                } else {
                    self?.feedback.show(
                        TasksStrings.text(decision.approve ? "tasks.decideFailed.approve" : "tasks.decideFailed.reject")
                    )
                }
            }
        }
    }

    /// The web's Admin Requests page, or nil (with a note) when no web app is configured.
    func webURL() -> URL? {
        guard let url = TasksWeb.url(Self.webPath, base: environment.webBaseURL) else {
            feedback.show(TasksStrings.text("tasks.web.unavailable"))
            return nil
        }
        return url
    }

    // MARK: Private

    private static let detailsKey = "details"
    private static let certificateKey = "certificate"

    private func loadDetails(_ request: ChangeRequest) {
        let requests = environment.requests
        bag.replace(Self.detailsKey) { [weak self] in
            if request.kind == .trainingCredit {
                let credit = try? await requests.trainingCredit(requestId: request.id)
                guard let self, !Task.isCancelled else { return }
                self.training = credit.map { Loadable<TrainingCredit>.ready($0) } ?? .failed
                self.rebuild()
            } else if request.kind.isTimeOff {
                await self?.loadLeaveZone()
                guard let timeOff = request.timeOff, let employee = request.requesterId else {
                    guard let self, !Task.isCancelled else { return }
                    self.balance = .ready(nil)
                    self.rebuild()
                    return
                }
                let result: Loadable<BalanceChange?>
                do {
                    let balance = try await requests.leaveBalance(
                        employeeId: employee,
                        leaveTypeId: timeOff.leaveTypeId
                    )
                    let cancelling = request.kind == .timeOffCancellation
                    result = .ready(RequestItems.balance(balance, timeOff: timeOff, cancellation: cancelling))
                } catch {
                    result = .failed
                }
                guard let self, !Task.isCancelled else { return }
                // A reviewer who may not see balances gets nil; a failed load offers a retry.
                self.balance = result
                self.rebuild()
            }
        }
    }

    /// Asked once: reviewers who aren't leave administrators can't read it, and the answer won't change.
    private func loadLeaveZone() async {
        guard !leaveZoneAsked else { return }
        leaveZoneAsked = true
        if let zone = await environment.requests.leaveZone() {
            leaveZone = zone
            rebuild()
        }
    }

    private func load(refreshing: Bool) async {
        isRefreshing = refreshing
        waitingFailed = false
        rebuild()
        do {
            try await environment.requests.refreshWaiting()
        } catch {
            waitingFailed = true
        }
        await loadMine()
        // Cards word partial days in the leave zone too, so it loads with the lists.
        let all = (waiting ?? []) + (mine.value ?? [])
        if all.contains(where: { $0.timeOff?.partialDay == true }) { await loadLeaveZone() }
        isRefreshing = false
        rebuild()
    }

    private func loadMine() async {
        do {
            mine = .ready(try await environment.requests.mine())
        } catch {
            // A failed refresh keeps the last good list.
            if mine.value == nil { mine = .failed }
        }
        rebuild()
    }

    private func rebuild() {
        let zone = environment.calendar.scheduleTimeZone().zone
        let today = CalendarDate(environment.clock.now, in: zone)
        // Partial days are told in the agency's leave zone, as on the web; the person's own zone
        // stands in when the leave settings can't be read.
        let leave = leaveZone ?? zone
        let items = waiting?.map { RequestItems.item($0, zone: zone, leaveZone: leave, today: today) }
        var next = RequestsScreenState()
        next.waiting =
            if let items { .ready(items) } else if waitingFailed { .failed } else { .loading }
        next.mine = mine.map { $0.map { RequestItems.item($0, zone: zone, leaveZone: leave, today: today) } }
        // A request decided elsewhere closes its sheet instead of offering a stale review.
        next.reviewing = reviewingId.flatMap { id in items?.first { $0.id == id } }
        next.confirming = confirming.flatMap { pick in
            items?.first { $0.id == pick.id }.map { Decision(item: $0, approve: pick.approve) }
        }
        next.isRefreshing = isRefreshing
        next.balance = balance
        next.training = training
        next.reason = reason
        next.openingCertificate = openingCertificate
        next.certificate = certificate
        if next != state { state = next }
    }
}
