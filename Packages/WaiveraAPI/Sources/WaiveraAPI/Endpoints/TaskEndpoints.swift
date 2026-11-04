import Foundation

/// The server's narrowing of one task list call.
public struct TaskListFilter: Sendable, Hashable {
    /// The person themself for their own work; nil lists everything their role may see.
    public var assignee: String?
    /// `Client` (casework) or `Employee` (the person's own work).
    public var taskContext: String
    public var includePendingApprovals: Bool?
    public var searchTerm: String
    /// `overdue`, `today`, `week` or `month`, judged on the server in the employee's saved zone.
    public var date: [String]
    /// `without-delays` or `delayed`; nil lists both.
    public var taskDelayFilter: String?

    public init(
        assignee: String?,
        taskContext: String,
        includePendingApprovals: Bool? = nil,
        searchTerm: String = "",
        date: [String] = [],
        taskDelayFilter: String? = nil
    ) {
        self.assignee = assignee
        self.taskContext = taskContext
        self.includePendingApprovals = includePendingApprovals
        self.searchTerm = searchTerm
        self.date = date
        self.taskDelayFilter = taskDelayFilter
    }
}

/// `Controllers/Tasks/TaskController.cs` (`api/tasks`) and `Controllers/TaskActionController.cs`
/// (`api/taskActions`): tasks the person may see, one task, its activity and files, and logging.
extension APIClient {
    public static let taskPageSize = 25

    public func tasks(
        userId: String,
        filter: TaskListFilter,
        page: Int,
        pageSize: Int = APIClient.taskPageSize
    ) async throws -> TaskPageResponse {
        var query: [URLQueryItem] = []
        if let assignee = filter.assignee { query.append(URLQueryItem(name: "assignee", value: assignee)) }
        query.append(URLQueryItem(name: "taskContext", value: filter.taskContext))
        if let include = filter.includePendingApprovals {
            query.append(URLQueryItem(name: "includePendingApprovals", value: include ? "true" : "false"))
        }
        query.append(URLQueryItem(name: "searchTerm", value: filter.searchTerm))
        query += filter.date.map { URLQueryItem(name: "date", value: $0) }
        if let delays = filter.taskDelayFilter { query.append(URLQueryItem(name: "taskDelayFilter", value: delays)) }
        // Closed tasks never show, and the soonest due comes first, as on the web.
        query.append(URLQueryItem(name: "excludeStatus", value: "CLOSED"))
        query.append(URLQueryItem(name: "sort", value: "due:asc"))
        query.append(URLQueryItem(name: "page", value: String(max(1, page))))
        query.append(URLQueryItem(name: "pageSize", value: String(pageSize)))
        return try await decode(APIRequest(.get, "api/tasks/user/\(escape(userId))", query: query))
    }

    public func task(id: Int) async throws -> TaskResponse {
        try await decode(APIRequest(.get, "api/tasks/\(id)"))
    }

    /// A task by the number people see, in the caller's agency, with the same access checks.
    public func lookupTask(friendlyId: Int) async throws -> TaskResponse {
        try await decode(APIRequest(.get, "api/tasks/lookup/\(friendlyId)"))
    }

    public func taskActivity(taskId: Int) async throws -> [TaskActionResponse] {
        try await decode(APIRequest(.get, "api/tasks/\(taskId)/actions"), as: LossyArray<TaskActionResponse>.self)
            .elements
    }

    public func activityTypes() async throws -> [ActionSubTypeResponse] {
        try await decode(APIRequest(.get, "api/taskActions/actionSubTypes"), as: LossyArray<ActionSubTypeResponse>.self)
            .elements
    }

    /// Enveloped `ApiResponse<int?>`; a `success: false` inside a 200 throws.
    public func logActivity(_ request: TaskActionRequest) async throws {
        _ = try await envelopedIfPresent(try .json(.post, "api/taskActions/new", body: request), as: JSONValue.self)
    }

    public func taskAttachments(taskId: Int) async throws -> [TaskAttachmentResponse] {
        try await decode(
            APIRequest(.get, "api/tasks/attachments/\(taskId)"),
            as: LossyArray<TaskAttachmentResponse>.self
        )
        .elements
    }

    /// A case file's bytes, or an employee file attached to an employee task (checked against it).
    public func taskFileBytes(taskId: Int, fileId: String, employeeFile: Bool) async throws -> Data {
        let path =
            employeeFile
            ? "api/employee-file/task-view/\(taskId)/\(escape(fileId))"
            : "api/file/download/\(escape(fileId))"
        return try await send(APIRequest(.get, path, accept: "*/*"))
    }
}

/// Change requests on tasks and their review: `AdmininistrativeTransactionController.cs`,
/// `TaskExtensionController.cs`, `TaskDelayController.cs`, the eligibility and reason
/// controllers, and `TaskController.cs` (`request-close`). The server scopes every list to what
/// the caller may see and re-checks every write.
extension APIClient {
    public static let requestPageSize = 50

    public func authBootstrap() async throws -> AuthBootstrapResponse {
        try await enveloped(try .json(.post, "api/Authentication/bootstrap", body: AuthBootstrapRequest()))
    }

    public func myRequests(page: Int = 1) async throws -> PagedResults<AdminRequestResponse> {
        let query = [
            URLQueryItem(name: "PageNumber", value: String(page)),
            URLQueryItem(name: "PageSize", value: String(APIClient.requestPageSize)),
            URLQueryItem(name: "NeedTimeOffRequests", value: "false"),
        ]
        return try await enveloped(APIRequest(.get, "api/admin/request/self", query: query))
    }

    /// Pending requests this person may act on; an empty type name asks for every kind.
    public func waitingRequests(page: Int = 1) async throws -> PagedResults<AdminRequestResponse> {
        let query = [
            URLQueryItem(name: "pageNumber", value: String(page)),
            URLQueryItem(name: "pageSize", value: String(APIClient.requestPageSize)),
            URLQueryItem(name: "transactionalTypeName", value: ""),
        ]
        return try await enveloped(APIRequest(.get, "api/admin/request/pending-approvals", query: query))
    }

    public func decideRequest(id: Int, approve: Bool) async throws {
        let path = approve ? "api/admin/request/approve/\(id)" : "api/admin/request/reject/\(id)"
        try await checkEnvelope(APIRequest(.put, path))
    }

    public func complianceEligibility(taskId: Int) async throws -> ComplianceEligibilityResponse {
        try await decode(APIRequest(.get, "api/tasks/\(taskId)/compliance-request-eligibility"))
    }

    public func complianceReasons() async throws -> [ComplianceReasonResponse] {
        try await decode(
            APIRequest(.get, "api/settings/organization/compliance/reasons"),
            as: LossyArray<ComplianceReasonResponse>.self
        )
        .elements
    }

    public func closureReasons() async throws -> [TransactionReasonResponse] {
        try await decode(
            APIRequest(.get, "api/lookup/reasons", query: [URLQueryItem(name: "type", value: "CLOSURE")]),
            as: LossyArray<TransactionReasonResponse>.self
        )
        .elements
    }

    /// Bare `{ adjustmentId, status }`, not enveloped.
    public func askMoreTime(taskId: Int, _ body: TaskExtensionRequest) async throws -> ComplianceRequestResult {
        try await decode(try .json(.post, "api/tasks/\(taskId)/extensions", body: body))
    }

    public func reportDelay(taskId: Int, _ body: TaskDelayRequest) async throws -> ComplianceRequestResult? {
        try await envelopedIfPresent(try .json(.post, "api/tasks/\(taskId)/delays", body: body))
    }

    public func askClosure(taskId: Int, _ body: TaskClosureRequest) async throws {
        try await checkEnvelope(try .json(.post, "api/tasks/\(taskId)/request-close", body: body))
    }

    /// Some writes answer with a bare body and some with an envelope that can say no inside a 200.
    /// The envelope's own message is never shown.
    private func checkEnvelope(_ request: APIRequest) async throws {
        let data = try await send(request)
        guard !data.isEmpty, let body = try? WaiveraJSON.decoder().decode(JSONValue.self, from: data) else { return }
        if case .bool(false) = body["success"] { throw WaiveraError.invalidResponse }
    }
}
