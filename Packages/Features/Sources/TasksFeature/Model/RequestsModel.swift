import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// What a request changes, already worded for the person's day.
enum RequestChange: Hashable, Sendable {
    /// More time: the due date moves from `from` to `to`, `daysLater` days later.
    case dueMove(from: String?, to: String, daysLater: Int?)
    /// A delay recorded for a server-owned period; the due date stays.
    case delayWindow(start: String, end: String)
    /// Closure: the task closes without being completed.
    case closure
    /// Time off, profile changes and the rest, which the web reviews.
    case other

    var text: String? {
        switch self {
        case .dueMove(let from, let to, _):
            from.map { TasksStrings.format("tasks.change.dueMove", $0, to) }
                ?? TasksStrings.format("tasks.change.dueTo", to)
        case .delayWindow(let start, let end): TasksStrings.format("tasks.change.delay", start, end)
        case .closure: TasksStrings.text("tasks.change.closure")
        case .other: nil
        }
    }
}

struct RequestItem: Identifiable, Hashable, Sendable {
    var request: ChangeRequest
    /// When it was asked, in the employee's saved zone.
    var asked: TaskMoment?
    var change: RequestChange
    /// Today's due text for the task in question, when the request carries its current due date.
    var due: DueText
    var id: Int { request.id }

    var kindLabel: String {
        switch request.kind {
        case .moreTime: TasksStrings.text("tasks.kind.moreTime")
        case .delay: TasksStrings.text("tasks.kind.delay")
        case .closure: TasksStrings.text("tasks.kind.closure")
        case .other: request.typeName
        }
    }

    var statusLabel: String {
        switch request.status {
        case .approved: TasksStrings.text("tasks.status.approved")
        case .rejected: TasksStrings.text("tasks.status.rejected")
        case .pending, .other: TasksStrings.text("tasks.status.pending")
        }
    }

    var reviewTitle: String {
        switch request.kind {
        case .moreTime: TasksStrings.text("tasks.review.title.moreTime")
        case .delay: TasksStrings.text("tasks.review.title.delay")
        case .closure, .other: TasksStrings.text("tasks.review.title.closure")
        }
    }

    /// The confirm sheet's title and what will happen, worded as the web's review dialogs are.
    func confirmation(approve: Bool) -> (title: String, message: String) {
        let task = request.taskTitle ?? TasksStrings.text("tasks.thisTask")
        let who = request.requesterName.isEmpty ? TasksStrings.text("tasks.theRequester") : request.requesterName
        let verb = approve ? "approve" : "reject"
        switch (request.kind, change) {
        case (.moreTime, .dueMove(let from, let to, _)):
            let title = TasksStrings.text("tasks.confirm.\(verb).title.moreTime")
            if approve {
                let message =
                    from.map { TasksStrings.format("tasks.confirm.approve.moreTime", task, to, $0, who) }
                    ?? TasksStrings.format("tasks.confirm.approve.moreTime.short", task, to, who)
                return (title, message)
            }
            let message =
                from.map { TasksStrings.format("tasks.confirm.reject.moreTime", task, $0, who) }
                ?? TasksStrings.format("tasks.confirm.reject.moreTime.short", task, who)
            return (title, message)
        case (.moreTime, _):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.moreTime"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.generic", task, who)
                    : TasksStrings.format("tasks.confirm.reject.moreTime.short", task, who)
            )
        case (.delay, .delayWindow(let start, let end)):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.delay"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.delay", start, end, task, who)
                    : TasksStrings.format("tasks.confirm.reject.delay", task, who)
            )
        case (.delay, _):
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.delay"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.generic", task, who)
                    : TasksStrings.format("tasks.confirm.reject.delay", task, who)
            )
        default:
            return (
                TasksStrings.text("tasks.confirm.\(verb).title.closure"),
                approve
                    ? TasksStrings.format("tasks.confirm.approve.closure", task, who)
                    : TasksStrings.format("tasks.confirm.reject.closure", task, who)
            )
        }
    }
}

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
}

/// The Requests segment (Android `RequestsViewModel`): requests waiting on this person, then
/// their own. Approve and reject are optimistic: the card leaves at once and comes back, with a
/// note, if the server says no.
@MainActor
@Observable
final class RequestsModel {
    static let webPath = "/admin-requests"

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
        rebuild()
        return nil
    }

    func closeReview() {
        reviewingId = nil
        confirming = nil
        rebuild()
    }

    func ask(approve: Bool) {
        guard let id = reviewingId else { return }
        confirming = (id, approve)
        rebuild()
    }

    func cancelConfirm() {
        confirming = nil
        rebuild()
    }

    /// Sends the confirmed decision. Both sheets close at once; the list already shows the result.
    func confirm() {
        guard let decision = state.confirming else { return }
        reviewingId = nil
        confirming = nil
        rebuild()
        let requests = environment.requests
        bag.run { [weak self] in
            do {
                try await requests.decide(decision.item.request, approve: decision.approve)
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
        let items = waiting?.map { Self.item($0, zone: zone, today: today) }
        var next = RequestsScreenState()
        next.waiting =
            if let items { .ready(items) } else if waitingFailed { .failed } else { .loading }
        next.mine = mine.map { $0.map { Self.item($0, zone: zone, today: today) } }
        // A request decided elsewhere closes its sheet instead of offering a stale review.
        next.reviewing = reviewingId.flatMap { id in items?.first { $0.id == id } }
        next.confirming = confirming.flatMap { pick in
            items?.first { $0.id == pick.id }.map { Decision(item: $0, approve: pick.approve) }
        }
        next.isRefreshing = isRefreshing
        if next != state { state = next }
    }

    static func item(_ request: ChangeRequest, zone: TimeZone, today: CalendarDate) -> RequestItem {
        RequestItem(
            request: request,
            asked: request.requestedAt.map { TaskFormat.moment($0, zone: zone, today: today) },
            change: change(request, today: today),
            due: TaskFormat.due(request.currentDue, today: today)
        )
    }

    static func change(_ request: ChangeRequest, today: CalendarDate) -> RequestChange {
        switch request.kind {
        case .moreTime:
            guard let to = request.requestedDue else { return .other }
            let later = request.currentDue.map { $0.days(until: to) }.flatMap { $0 > 0 ? $0 : nil }
            return .dueMove(
                from: request.currentDue.map { TaskFormat.date($0, today: today) },
                to: TaskFormat.date(to, today: today),
                daysLater: later
            )
        case .delay:
            guard let start = request.delayStart, let end = request.delayEnd else { return .other }
            return .delayWindow(start: TaskFormat.date(start, today: today), end: TaskFormat.date(end, today: today))
        case .closure:
            return .closure
        case .other:
            return .other
        }
    }
}
