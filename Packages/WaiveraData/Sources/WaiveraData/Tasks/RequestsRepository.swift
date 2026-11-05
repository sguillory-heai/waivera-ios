import Foundation
import WaiveraAPI

/// Change requests on tasks: asking for more time, reporting a delay or asking to close, and
/// reviewing what others asked. `waiting` is shared by every screen that shows it, so a decision
/// leaves all of them at once and comes back to all of them if the server refuses it.
public protocol RequestsRepository: Sendable {
    /// What to offer, re-checked when the person signs in, returns to the app, or refreshes.
    func access() -> AsyncStream<RequestAccess>
    func currentAccess() async -> RequestAccess
    /// Requests waiting on this person, newest first; nil until first loaded.
    func waiting() -> AsyncStream<[ChangeRequest]?>
    func refreshAccess() async throws
    /// Loads access only when it has not been loaded for this session yet; failures leave it unloaded.
    func ensureAccess() async
    func refreshWaiting() async throws
    /// The person's own requests, newest first.
    func mine() async throws -> [ChangeRequest]
    /// Removes the request from `waiting` at once and puts it back if the server says no.
    /// Training credit needs the credit's revision (and reason); other kinds ignore it.
    func decide(_ request: ChangeRequest, approve: Bool, training: TrainingDecision?) async throws
    /// The requester's balance for one leave type; nil when this reviewer may not see balances.
    func leaveBalance(employeeId: String, leaveTypeId: Int) async throws -> LeaveBalance?
    /// The agency's leave zone, the one partial days are told in; nil when unknown.
    func leaveZone() async -> TimeZone?
    func trainingCredit(requestId: Int) async throws -> TrainingCredit
    /// The certificate's bytes and file name, for the file sheet.
    func trainingCertificate(requestId: Int) async throws -> DownloadedFile
    /// The agency's leave types, each with the person's own balance when it can be read.
    func leaveTypes() async throws -> [LeaveType]
    func previewLeave(_ draft: LeaveDraft) async throws -> LeavePreview
    /// Sends `draft` for approval; a refusal the app can word throws `LeaveSendError`.
    func requestTimeOff(_ draft: LeaveDraft) async throws
    func options(taskId: Int) async throws -> ChangeOptions
    func moreTimeReasons() async throws -> [ChangeReason]
    func delayReasons() async throws -> [ChangeReason]
    func closureReasons() async throws -> [ChangeReason]
    func files(taskId: Int) async throws -> [TaskFileRef]
    func askMoreTime(
        taskId: Int,
        newDue: CalendarDate,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome
    func reportDelay(
        taskId: Int,
        period: DelayPeriod,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome
    func askClosure(taskId: Int, reasonId: Int64, comment: String) async throws
}

extension RequestsRepository {
    public func decide(_ request: ChangeRequest, approve: Bool) async throws {
        try await decide(request, approve: approve, training: nil)
    }
}

/// A file fetched to open, save or share.
public struct DownloadedFile: Sendable, Hashable {
    public var data: Data
    public var name: String
    public var mimeType: String?

    public init(data: Data, name: String, mimeType: String?) {
        self.data = data
        self.name = name
        self.mimeType = mimeType
    }
}

/// Change requests straight from sprout_api; nothing is stored on the device. What to offer is
/// loaded from `Authentication/bootstrap` when someone signs in and each time the app comes back
/// to the foreground, so a role change on the web reaches the phone without signing out.
public actor LiveRequestsRepository: RequestsRepository {
    private let api: APIClient
    private let context: SessionContext
    private let accessCell = StateCell(RequestAccess())
    private let waitingCell = StateCell<[ChangeRequest]?>(nil)
    /// Requests decided on this device whose answer is still out, so a refresh cannot bring them back.
    private var deciding: Set<Int> = []
    /// Counts finished decisions; `decided` maps each recently decided id to the count when its
    /// answer came back. A page that started before that may still list it, so it is left out
    /// of that page; a page that started after it is the server's word and lets it go.
    private var decisions = 0
    private var decided: [Int: Int] = [:]
    /// Pages land in the order they were asked for: one overtaken by a newer page is dropped.
    private var pagesAsked = 0
    private var pageShown = 0
    private var accessLoad: Task<Void, any Error>?
    /// Bumped on sign-out, so an answer still in flight never lands on the next account.
    private var generation = 0

    public init(api: APIClient, context: SessionContext) {
        self.api = api
        self.context = context
    }

    nonisolated public func access() -> AsyncStream<RequestAccess> { accessCell.stream() }
    nonisolated public func waiting() -> AsyncStream<[ChangeRequest]?> { waitingCell.stream() }
    public func currentAccess() -> RequestAccess { accessCell.current }

    public func refreshAccess() async throws {
        if let running = accessLoad { return try await running.value }
        let started = generation
        let task = Task { [api] in
            let bootstrap = try await api.authBootstrap()
            try Task.checkCancellation()
            self.store(access: RequestMapping.access(bootstrap), generation: started)
        }
        accessLoad = task
        defer { accessLoad = nil }
        try await task.value
    }

    private func store(access: RequestAccess, generation started: Int) {
        guard generation == started else { return }
        accessCell.set(access)
    }

    // Callers that only need access loaded share one bootstrap call instead of queueing several.
    public func ensureAccess() async {
        guard !accessCell.current.loaded else { return }
        try? await refreshAccess()
    }

    public func refreshWaiting() async throws {
        guard context.currentUser != nil else { throw WaiveraError.signedOut }
        let started = generation
        pagesAsked += 1
        let pageNumber = pagesAsked
        let decisionsBefore = decisions
        let page = try await api.waitingRequests()
        guard generation == started, pageNumber > pageShown else { return }
        pageShown = pageNumber
        decided = decided.filter { $0.value > decisionsBefore }
        let hidden = deciding.union(decided.keys)
        waitingCell.set(page.items.map(RequestMapping.request).filter { !hidden.contains($0.id) })
    }

    private func finishedDeciding(_ id: Int) {
        decisions += 1
        decided[id] = decisions
    }

    public func mine() async throws -> [ChangeRequest] {
        try await api.myRequests().items.map(RequestMapping.request)
    }

    public func decide(_ request: ChangeRequest, approve: Bool, training: TrainingDecision?) async throws {
        let order = (waitingCell.current ?? []).map(\.id)
        deciding.insert(request.id)
        waitingCell.update { $0 = $0?.filter { $0.id != request.id } }
        defer { deciding.remove(request.id) }
        do {
            try await send(request, approve: approve, training: training)
            finishedDeciding(request.id)
        } catch {
            let failure = WaiveraError.from(error)
            // Someone else already decided it: it stays gone. Anything else puts it back where it was.
            if failure == .notFound {
                finishedDeciding(request.id)
            } else {
                waitingCell.update { current in
                    var list = current ?? []
                    guard !list.contains(where: { $0.id == request.id }) else { return }
                    list.append(request)
                    let rank = { (id: Int) in order.firstIndex(of: id) ?? Int.max }
                    current = list.sorted { rank($0.id) < rank($1.id) }
                }
            }
            throw failure
        }
    }

    /// sprout_web `AdminRequestsPanel.handleApproveReject` and `ExternalTrainingReview.decide`.
    private func send(_ request: ChangeRequest, approve: Bool, training: TrainingDecision?) async throws {
        // The web's fixed wording; it asks the reviewer for no reason on these.
        let action = RequestActionBody(
            action: approve ? "approve" : "reject",
            reason: approve ? "Approved via Admin Panel" : "Rejected via Admin Panel"
        )
        switch request.kind {
        case .timeOff, .timeOffCancellation:
            try await api.decideTimeOff(id: request.id, action)
        case .profileChange:
            try await api.decideProfileChange(id: request.id, action)
        case .trainingCredit:
            // A training decision needs the credit's revision.
            guard let training else { throw WaiveraError.invalidResponse }
            let body = TrainingDecisionBody(
                revision: training.revision,
                approve: approve,
                reason: training.reason.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try await api.decideTrainingCredit(requestId: request.id, body)
        case .other:
            // The web's other requests stay on the web.
            throw WaiveraError.invalidResponse
        default:
            try await api.decideRequest(id: request.id, approve: approve)
        }
    }

    public func leaveBalance(employeeId: String, leaveTypeId: Int) async throws -> LeaveBalance? {
        // Balances are for leave administrators; other reviewers decide without them, as on the web.
        let summary: LeaveBalancesResponse
        do {
            summary = try await api.leaveBalances(employeeId: employeeId)
        } catch {
            if WaiveraError.from(error) == .forbidden { return nil }
            throw WaiveraError.from(error)
        }
        return (summary.balances ?? []).first { $0.id == leaveTypeId }.map(ApprovalMapping.balance)
    }

    public func leaveZone() async -> TimeZone? {
        guard let name = try? await api.leaveSettings().timeZone else { return nil }
        return TimeZone(identifier: name)
    }

    public func trainingCredit(requestId: Int) async throws -> TrainingCredit {
        ApprovalMapping.training(requestId: requestId, try await api.trainingCredit(requestId: requestId))
    }

    public func trainingCertificate(requestId: Int) async throws -> DownloadedFile {
        let (data, response) = try await api.trainingCertificate(requestId: requestId)
        return DownloadedFile(
            data: data,
            // The server only takes PDF certificates.
            name: "Certificate.pdf",
            mimeType: response.mimeType ?? "application/pdf"
        )
    }

    public func leaveTypes() async throws -> [LeaveType] {
        guard let me = context.currentUser?.id else { throw WaiveraError.signedOut }
        async let types = api.leaveTypes()
        // A person may always read their own balances; without them the types still list.
        async let balances = try? api.leaveBalances(employeeId: me).balances
        return LeaveMapping.leaveTypes(try await types, balances: await balances ?? nil)
    }

    public func previewLeave(_ draft: LeaveDraft) async throws -> LeavePreview {
        guard let me = context.currentUser?.id else { throw WaiveraError.signedOut }
        let body = LeavePreviewBody(
            employeeId: me,
            leaveTypeId: draft.leaveTypeId,
            startTime: LeaveMapping.iso(draft.start),
            endTime: LeaveMapping.iso(draft.end),
            requestType: draft.partialDay ? Self.partialDay : Self.fullDay
        )
        return LeaveMapping.preview(try await api.previewLeave(body))
    }

    public func requestTimeOff(_ draft: LeaveDraft) async throws {
        guard let me = context.currentUser?.id else { throw WaiveraError.signedOut }
        let note = draft.note?.trimmingCharacters(in: .whitespacesAndNewlines)
        let body = TimeOffBody(
            userId: me,
            typeOfLeave: draft.leaveTypeId,
            comment: note?.isEmpty == false ? note : nil,
            timeOffStartTime: LeaveMapping.iso(draft.start),
            timeOffEndTime: LeaveMapping.iso(draft.end),
            requestType: draft.partialDay ? Self.partialDay : Self.fullDay
        )
        do {
            try await api.requestTimeOff(body)
        } catch let refusal as CodedRefusal {
            // Refusals the person can fix get the app's own words; everything else stays a WaiveraError.
            if let problem = LeaveMapping.sendProblem(refusal.error, code: refusal.code) {
                throw LeaveSendError(problem: problem)
            }
            throw refusal.error
        } catch {
            throw WaiveraError.from(error)
        }
    }

    private static let fullDay = "FULL_DAY"
    private static let partialDay = "PARTIAL_DAY"

    public func options(taskId: Int) async throws -> ChangeOptions {
        RequestMapping.options(try await api.complianceEligibility(taskId: taskId), taskId: taskId)
    }

    public func moreTimeReasons() async throws -> [ChangeReason] {
        RequestMapping.reasons(try await api.complianceReasons(), forDelay: false)
    }

    public func delayReasons() async throws -> [ChangeReason] {
        RequestMapping.reasons(try await api.complianceReasons(), forDelay: true)
    }

    public func closureReasons() async throws -> [ChangeReason] {
        RequestMapping.closureReasons(try await api.closureReasons())
    }

    public func files(taskId: Int) async throws -> [TaskFileRef] {
        RequestMapping.files(try await api.taskAttachments(taskId: taskId))
    }

    public func askMoreTime(
        taskId: Int,
        newDue: CalendarDate,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome {
        // The web sends the picked day at UTC midnight; the server keeps it as a UTC date.
        let body = TaskExtensionRequest(
            requestedDueDate: "\(newDue.isoString)T00:00:00Z",
            reasonCodeId: reasonId,
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            evidenceAttachmentId: evidenceId
        )
        return Self.outcome(try await api.askMoreTime(taskId: taskId, body).status)
    }

    public func reportDelay(
        taskId: Int,
        period: DelayPeriod,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome {
        let body = TaskDelayRequest(
            reasonCodeId: reasonId,
            explanation: explanation.trimmingCharacters(in: .whitespacesAndNewlines),
            delayStartDate: period.start.isoString,
            delayEndDate: period.end.isoString,
            evidenceAttachmentId: evidenceId
        )
        return Self.outcome(try await api.reportDelay(taskId: taskId, body)?.status)
    }

    public func askClosure(taskId: Int, reasonId: Int64, comment: String) async throws {
        guard let me = context.currentUser?.id else { throw WaiveraError.signedOut }
        // As the web's closure modal: the reason goes by id, the text is the comment.
        let body = TaskClosureRequest(
            requesterId: me,
            taskId: taskId,
            transactionReasonId: Int(reasonId),
            transactionReasonText: comment.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try await api.askClosure(taskId: taskId, body)
    }

    /// Signed in, or back in the foreground: re-read what to offer and what waits.
    public func refreshAll() async {
        try? await refreshAccess()
        try? await refreshWaiting()
    }

    /// Nothing from one account outlives its session.
    public func reset() {
        generation += 1
        accessLoad?.cancel()
        accessLoad = nil
        deciding = []
        decided = [:]
        accessCell.set(RequestAccess())
        waitingCell.set(nil)
    }

    private static func outcome(_ status: String?) -> RequestOutcome {
        status?.caseInsensitiveCompare("Approved") == .orderedSame ? .approved : .pending
    }
}

/// No requests: for previews and environments without the request API.
public struct EmptyRequestsRepository: RequestsRepository {
    public init() {}

    public func access() -> AsyncStream<RequestAccess> {
        AsyncStream { $0.yield(RequestAccess(loaded: true)) }
    }
    public func currentAccess() async -> RequestAccess { RequestAccess(loaded: true) }
    public func waiting() -> AsyncStream<[ChangeRequest]?> { AsyncStream { $0.yield([]) } }
    public func refreshAccess() async throws {}
    public func ensureAccess() async {}
    public func refreshWaiting() async throws {}
    public func mine() async throws -> [ChangeRequest] { [] }
    public func decide(_ request: ChangeRequest, approve: Bool, training: TrainingDecision?) async throws {
        throw WaiveraError.notFound
    }
    public func leaveBalance(employeeId: String, leaveTypeId: Int) async throws -> LeaveBalance? { nil }
    public func leaveZone() async -> TimeZone? { nil }
    public func trainingCredit(requestId: Int) async throws -> TrainingCredit { throw WaiveraError.notFound }
    public func trainingCertificate(requestId: Int) async throws -> DownloadedFile { throw WaiveraError.notFound }
    public func leaveTypes() async throws -> [LeaveType] { [] }
    public func previewLeave(_ draft: LeaveDraft) async throws -> LeavePreview { throw WaiveraError.notFound }
    public func requestTimeOff(_ draft: LeaveDraft) async throws { throw WaiveraError.notFound }
    public func options(taskId: Int) async throws -> ChangeOptions {
        ChangeOptions(taskId: taskId, currentDue: nil, canAskMoreTime: false, delay: nil, hasPendingRequest: false)
    }
    public func moreTimeReasons() async throws -> [ChangeReason] { [] }
    public func delayReasons() async throws -> [ChangeReason] { [] }
    public func closureReasons() async throws -> [ChangeReason] { [] }
    public func files(taskId: Int) async throws -> [TaskFileRef] { [] }
    public func askMoreTime(
        taskId: Int,
        newDue: CalendarDate,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome { throw WaiveraError.notFound }
    public func reportDelay(
        taskId: Int,
        period: DelayPeriod,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?
    ) async throws -> RequestOutcome { throw WaiveraError.notFound }
    public func askClosure(taskId: Int, reasonId: Int64, comment: String) async throws {
        throw WaiveraError.notFound
    }
}
