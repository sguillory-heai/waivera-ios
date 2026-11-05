import Foundation
import WaiveraAPI

/// Tasks straight from `api/tasks`; nothing is cached, so the web and the phone never disagree.
public protocol TasksRepository: Sendable {
    func tasks(_ query: TaskQuery, page: Int) async throws -> TaskPage
    /// How many open tasks a list holds, how many are overdue, and (casework) how many are delayed.
    func counts(scope: TaskScope, assignedToMe: Bool) async throws -> TaskCounts
    func task(id: Int) async throws -> TaskDetail
    /// Oldest first.
    func activity(taskId: Int) async throws -> [TaskActivity]
    func activityTypes() async throws -> [ActivityType]
    func logActivity(_ activity: NewActivity) async throws
    /// The task's files, newest first.
    func attachments(taskId: Int) async throws -> [TaskAttachment]
    /// A file's bytes, held in memory only while the viewer shows it; nothing is written to disk.
    func fileData(taskId: Int, attachment: TaskAttachment) async throws -> Data
    /// The same bytes for a copy to save or share, up to `TaskAttachment.maxExportBytes`.
    func fileExport(taskId: Int, attachment: TaskAttachment) async throws -> Data
}

public struct LiveTasksRepository: TasksRepository {
    private static let clientContext = "Client"
    private static let employeeContext = "Employee"

    private let api: APIClient
    private let context: SessionContext
    private let requests: any RequestsRepository

    public init(api: APIClient, context: SessionContext, requests: any RequestsRepository) {
        self.api = api
        self.context = context
        self.requests = requests
    }

    public func tasks(_ query: TaskQuery, page: Int) async throws -> TaskPage {
        let filter = try await filter(
            scope: query.scope,
            assignedToMe: query.assignedToMe,
            search: query.search,
            window: query.window,
            delays: query.scope == .casework ? query.delays : .show
        )
        let response = try await api.tasks(userId: try me(), filter: filter, page: page)
        return TaskPage(items: response.tasks.map(TaskMapping.summary), totalCount: response.totalCount)
    }

    public func counts(scope: TaskScope, assignedToMe: Bool) async throws -> TaskCounts {
        let user = try me()
        let casework = scope == .casework
        let all = try await filter(scope: scope, assignedToMe: assignedToMe, window: .allOpen, delays: .show)
        // A delayed task is not really overdue, so overdue leaves delays out as the web's to-dos do.
        let late = try await filter(
            scope: scope,
            assignedToMe: assignedToMe,
            window: .overdue,
            delays: casework ? .hide : .show
        )
        let delayedFilter = try await filter(scope: scope, assignedToMe: assignedToMe, window: .allOpen, delays: .only)
        async let open = api.tasks(userId: user, filter: all, page: 1, pageSize: 1)
        async let overdue = api.tasks(userId: user, filter: late, page: 1, pageSize: 1)
        let delayed = casework ? try await api.tasks(userId: user, filter: delayedFilter, page: 1, pageSize: 1) : nil
        return TaskCounts(
            open: try await open.totalCount,
            overdue: try await overdue.totalCount,
            delayed: delayed?.totalCount ?? 0
        )
    }

    /// Casework is the web's client task list: the server scopes it by role, with pending
    /// approvals for the roles the web includes them for. My work is the person's own employee tasks.
    private func filter(
        scope: TaskScope,
        assignedToMe: Bool,
        search: String = "",
        window: TaskWindow,
        delays: DelayFilter
    ) async throws -> TaskListFilter {
        let user = try me()
        let casework = scope == .casework
        var include: Bool?
        if casework {
            await requests.ensureAccess()
            include = await requests.currentAccess().includePendingApprovals
        }
        return TaskListFilter(
            assignee: casework && !assignedToMe ? nil : user,
            taskContext: casework ? Self.clientContext : Self.employeeContext,
            includePendingApprovals: include,
            searchTerm: search.trimmingCharacters(in: .whitespacesAndNewlines),
            date: window.dateFilter,
            taskDelayFilter: casework ? delays.serverValue : nil
        )
    }

    public func task(id: Int) async throws -> TaskDetail {
        TaskMapping.detail(try await api.task(id: id))
    }

    public func activity(taskId: Int) async throws -> [TaskActivity] {
        TaskMapping.activity(try await api.taskActivity(taskId: taskId))
    }

    public func activityTypes() async throws -> [ActivityType] {
        let types = try await api.activityTypes()
        // Without templates a file still goes up under its own name, as on the web.
        let templates =
            types.contains { ($0.requiresFile ?? 0) > 0 } ? ((try? await api.templateFiles()) ?? []) : []
        return TaskMapping.activityTypes(types, templates: templates)
    }

    public func logActivity(_ activity: NewActivity) async throws {
        try await api.logActivity(
            TaskActionRequest(
                taskId: activity.taskId,
                description: activity.description.trimmingCharacters(in: .whitespacesAndNewlines),
                subTypeId: activity.typeId,
                durationInMinutes: activity.minutes,
                completionTime: WaiveraInstant.format(activity.completedAt)
            )
        )
    }

    public func attachments(taskId: Int) async throws -> [TaskAttachment] {
        TaskMapping.attachments(try await api.taskAttachments(taskId: taskId))
    }

    public func fileData(taskId: Int, attachment: TaskAttachment) async throws -> Data {
        guard attachment.sizeBytes <= TaskAttachment.maxViewBytes else { throw WaiveraError.invalidRequest }
        return try await bytes(taskId: taskId, attachment: attachment)
    }

    public func fileExport(taskId: Int, attachment: TaskAttachment) async throws -> Data {
        guard attachment.sizeBytes <= TaskAttachment.maxExportBytes else { throw WaiveraError.invalidRequest }
        return try await bytes(taskId: taskId, attachment: attachment)
    }

    private func bytes(taskId: Int, attachment: TaskAttachment) async throws -> Data {
        try await api.taskFileBytes(
            taskId: taskId,
            fileId: attachment.fileId,
            employeeFile: attachment.employeeFile
        )
    }

    private func me() throws -> String {
        guard let user = context.currentUser else { throw WaiveraError.signedOut }
        return user.id
    }
}

/// No tasks: for previews and environments that have no task server.
public struct EmptyTasksRepository: TasksRepository {
    public init() {}

    public func tasks(_ query: TaskQuery, page: Int) async throws -> TaskPage { TaskPage(items: [], totalCount: 0) }
    public func counts(scope: TaskScope, assignedToMe: Bool) async throws -> TaskCounts {
        TaskCounts(open: 0, overdue: 0)
    }
    public func task(id: Int) async throws -> TaskDetail { throw WaiveraError.notFound }
    public func activity(taskId: Int) async throws -> [TaskActivity] { [] }
    public func activityTypes() async throws -> [ActivityType] { [] }
    public func logActivity(_ activity: NewActivity) async throws { throw WaiveraError.notFound }
    public func attachments(taskId: Int) async throws -> [TaskAttachment] { [] }
    public func fileData(taskId: Int, attachment: TaskAttachment) async throws -> Data {
        throw WaiveraError.notFound
    }

    public func fileExport(taskId: Int, attachment: TaskAttachment) async throws -> Data {
        throw WaiveraError.notFound
    }
}
