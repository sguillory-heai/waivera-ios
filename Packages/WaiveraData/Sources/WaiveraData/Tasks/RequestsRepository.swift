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
    func decide(_ request: ChangeRequest, approve: Bool) async throws
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

    public func decide(_ request: ChangeRequest, approve: Bool) async throws {
        let order = (waitingCell.current ?? []).map(\.id)
        deciding.insert(request.id)
        waitingCell.update { $0 = $0?.filter { $0.id != request.id } }
        defer { deciding.remove(request.id) }
        do {
            try await api.decideRequest(id: request.id, approve: approve)
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
    public func decide(_ request: ChangeRequest, approve: Bool) async throws { throw WaiveraError.notFound }
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
