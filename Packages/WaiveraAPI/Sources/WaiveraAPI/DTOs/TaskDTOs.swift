import Foundation

// Mirrors of the sprout_api task contract the phone reads. Fields the phone does not use are
// left out, and dates stay strings until mapping: start and due dates are literal calendar
// dates sent as `YYYY-MM-DDT00:00:00`, while activity times are UTC instants
// (timezone-standard.md, task comment timestamp boundary). Every field is optional so one odd
// row never fails a page.

/// `GET api/tasks/user/{userId}` returns `{ tasks, totalCount }`.
public struct TaskPageResponse: Decodable, Sendable {
    public var tasks: [TaskListResponse]
    public var totalCount: Int

    enum CodingKeys: String, CodingKey { case tasks, totalCount }

    public init(tasks: [TaskListResponse] = [], totalCount: Int = 0) {
        self.tasks = tasks
        self.totalCount = totalCount
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tasks = container.lenientArray(TaskListResponse.self, forKey: .tasks)
        totalCount = container.lenientInt(forKey: .totalCount) ?? 0
    }
}

/// `dto/Response/TaskListResponse.cs`.
public struct TaskListResponse: Decodable, Sendable, Hashable {
    public var id: Int
    public var friendlyId: Int?
    public var title: String?
    public var organization: TaskOrganizationResponse?
    public var subType: NamedStatusResponse?
    public var startDate: String?
    public var endDate: String?
    public var effectiveEndDate: String?
    public var taskStatus: NamedStatusResponse?
    public var participant: TaskParticipantResponse?
    public var subjectEmployee: TaskUserResponse?
    public var assignee: TaskUserResponse?
    /// Who the task is assigned to; list endpoints fill this, not `assignee`.
    public var assignees: [TaskAssignmentResponse]?
    public var taskContext: String?
    public var hasPendingDeletion: Bool?
    public var currentTaskDelay: TaskDelaySummaryResponse?

    public init(
        id: Int,
        friendlyId: Int? = nil,
        title: String? = nil,
        organization: TaskOrganizationResponse? = nil,
        subType: NamedStatusResponse? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        effectiveEndDate: String? = nil,
        taskStatus: NamedStatusResponse? = nil,
        participant: TaskParticipantResponse? = nil,
        subjectEmployee: TaskUserResponse? = nil,
        assignee: TaskUserResponse? = nil,
        assignees: [TaskAssignmentResponse]? = nil,
        taskContext: String? = nil,
        hasPendingDeletion: Bool? = nil,
        currentTaskDelay: TaskDelaySummaryResponse? = nil
    ) {
        self.id = id
        self.friendlyId = friendlyId
        self.title = title
        self.organization = organization
        self.subType = subType
        self.startDate = startDate
        self.endDate = endDate
        self.effectiveEndDate = effectiveEndDate
        self.taskStatus = taskStatus
        self.participant = participant
        self.subjectEmployee = subjectEmployee
        self.assignee = assignee
        self.assignees = assignees
        self.taskContext = taskContext
        self.hasPendingDeletion = hasPendingDeletion
        self.currentTaskDelay = currentTaskDelay
    }
}

/// `dto/Response/TaskResponse.cs`, the fields the task screen shows.
public struct TaskResponse: Decodable, Sendable, Hashable {
    public var id: Int
    public var friendlyId: Int?
    public var title: String?
    public var description: String?
    public var organization: TaskOrganizationResponse?
    public var subType: NamedStatusResponse?
    public var startDate: String?
    public var endDate: String?
    public var effectiveEndDate: String?
    public var taskStatus: NamedStatusResponse?
    public var participant: TaskParticipantResponse?
    public var reporter: TaskUserResponse?
    public var assignee: TaskUserResponse?
    public var assignees: [TaskAssignmentResponse]?
    public var subjectEmployee: TaskUserResponse?
    public var taskContext: String?
    /// Change requests on the task; a pending one shows on the task page.
    public var administrativeTransactionRequests: [AdminRequestResponse]?
    public var currentTaskDelay: TaskDelaySummaryResponse?
    /// Every required form, file and signature is done, so it can be submitted or approved.
    public var isTaskReady: Bool?
    public var capabilities: TaskCapabilitiesResponse?
    /// The approval stages in order, for the step the task is on.
    public var workflowBlueprint: [WorkflowStepResponse]?

    public init(
        id: Int,
        friendlyId: Int? = nil,
        title: String? = nil,
        description: String? = nil,
        organization: TaskOrganizationResponse? = nil,
        subType: NamedStatusResponse? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        effectiveEndDate: String? = nil,
        taskStatus: NamedStatusResponse? = nil,
        participant: TaskParticipantResponse? = nil,
        reporter: TaskUserResponse? = nil,
        assignee: TaskUserResponse? = nil,
        assignees: [TaskAssignmentResponse]? = nil,
        subjectEmployee: TaskUserResponse? = nil,
        taskContext: String? = nil,
        administrativeTransactionRequests: [AdminRequestResponse]? = nil,
        currentTaskDelay: TaskDelaySummaryResponse? = nil,
        isTaskReady: Bool? = nil,
        capabilities: TaskCapabilitiesResponse? = nil,
        workflowBlueprint: [WorkflowStepResponse]? = nil
    ) {
        self.id = id
        self.friendlyId = friendlyId
        self.title = title
        self.description = description
        self.organization = organization
        self.subType = subType
        self.startDate = startDate
        self.endDate = endDate
        self.effectiveEndDate = effectiveEndDate
        self.taskStatus = taskStatus
        self.participant = participant
        self.reporter = reporter
        self.assignee = assignee
        self.assignees = assignees
        self.subjectEmployee = subjectEmployee
        self.taskContext = taskContext
        self.administrativeTransactionRequests = administrativeTransactionRequests
        self.currentTaskDelay = currentTaskDelay
        self.isTaskReady = isTaskReady
        self.capabilities = capabilities
        self.workflowBlueprint = workflowBlueprint
    }
}

/// The organization on a task: only its abbreviation, for the `HEA-1042` label.
public struct TaskOrganizationResponse: Decodable, Sendable, Hashable {
    public var abbreviation: String?

    public init(abbreviation: String?) { self.abbreviation = abbreviation }
}

/// `StatusResponse` and `TaskSubTypeResponse`: an id and a name.
public struct NamedStatusResponse: Decodable, Sendable, Hashable {
    public var name: String?

    public init(name: String?) { self.name = name }
}

/// `TaskDelayListResponse`: the approved delay covering the caller's today. Literal dates.
public struct TaskDelaySummaryResponse: Decodable, Sendable, Hashable {
    public var reasonName: String?
    public var explanation: String?
    public var delayStartDate: String?
    public var delayEndDate: String?

    public init(
        reasonName: String? = nil,
        explanation: String? = nil,
        delayStartDate: String? = nil,
        delayEndDate: String? = nil
    ) {
        self.reasonName = reasonName
        self.explanation = explanation
        self.delayStartDate = delayStartDate
        self.delayEndDate = delayEndDate
    }
}

/// `ParticipantResponse`: the name, and the plan (CPOC) dates an approval step that updates them
/// checks new dates against. Both dates are literal calendar dates.
public struct TaskParticipantResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var firstName: String?
    public var lastName: String?
    public var cpocDate: String?
    public var cpocEndDate: String?

    public init(
        id: Int? = nil,
        firstName: String?,
        lastName: String?,
        cpocDate: String? = nil,
        cpocEndDate: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.cpocDate = cpocDate
        self.cpocEndDate = cpocEndDate
    }
}

/// `UserResponse`.
public struct TaskUserResponse: Decodable, Sendable, Hashable {
    public var id: String?
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?

    public init(id: String? = nil, firstName: String? = nil, lastName: String? = nil, displayName: String? = nil) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
    }

    enum CodingKeys: String, CodingKey { case id, firstName, lastName, displayName }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(LenientID.self, forKey: .id)?.value
        firstName = container.lenient(String.self, forKey: .firstName)
        lastName = container.lenient(String.self, forKey: .lastName)
        displayName = container.lenient(String.self, forKey: .displayName)
    }
}

/// `dto/Response/TaskAssignmentReponse.cs`: one person on a task, and in what role.
public struct TaskAssignmentResponse: Decodable, Sendable, Hashable {
    public var user: TaskUserResponse?
    public var isReporter: Bool
    public var isCoAssignee: Bool

    public init(user: TaskUserResponse?, isReporter: Bool = false, isCoAssignee: Bool = false) {
        self.user = user
        self.isReporter = isReporter
        self.isCoAssignee = isCoAssignee
    }

    enum CodingKeys: String, CodingKey { case user, isReporter, isCoAssignee }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        user = container.lenient(TaskUserResponse.self, forKey: .user)
        isReporter = container.lenientBool(forKey: .isReporter)
        isCoAssignee = container.lenientBool(forKey: .isCoAssignee)
    }
}

/// `TaskActionResponse` from `GET api/tasks/{taskId}/actions`.
public struct TaskActionResponse: Decodable, Sendable, Hashable {
    public var id: Int
    public var author: TaskUserResponse?
    public var description: String?
    public var actionSubType: ActionSubTypeResponse?
    public var createDate: String?
    public var completionTime: String?
    public var durationInMinutes: Int?
    public var deleted: Bool?
    public var parentTaskActionId: Int?

    public init(
        id: Int,
        author: TaskUserResponse? = nil,
        description: String? = nil,
        actionSubType: ActionSubTypeResponse? = nil,
        createDate: String? = nil,
        completionTime: String? = nil,
        durationInMinutes: Int? = nil,
        deleted: Bool? = nil,
        parentTaskActionId: Int? = nil
    ) {
        self.id = id
        self.author = author
        self.description = description
        self.actionSubType = actionSubType
        self.createDate = createDate
        self.completionTime = completionTime
        self.durationInMinutes = durationInMinutes
        self.deleted = deleted
        self.parentTaskActionId = parentTaskActionId
    }
}

/// `Models/ActionSubType.cs` from `GET api/taskActions/actionSubTypes`.
public struct ActionSubTypeResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var actionSubTypeName: String?
    public var recommendedTimeInMinutes: Int?
    public var description: String?
    public var requiresFile: Int?
    public var isUserLoggable: Bool?

    public init(
        id: Int? = nil,
        actionSubTypeName: String? = nil,
        recommendedTimeInMinutes: Int? = nil,
        description: String? = nil,
        requiresFile: Int? = nil,
        isUserLoggable: Bool? = nil
    ) {
        self.id = id
        self.actionSubTypeName = actionSubTypeName
        self.recommendedTimeInMinutes = recommendedTimeInMinutes
        self.description = description
        self.requiresFile = requiresFile
        self.isUserLoggable = isUserLoggable
    }
}

/// `dto/Request/TaskActionRequest.cs` for `POST api/taskActions/new`. `completionTime` is ISO UTC.
public struct TaskActionRequest: Encodable, Sendable, Hashable {
    public var taskId: Int
    public var description: String
    public var subTypeId: Int
    public var durationInMinutes: Int
    public var completionTime: String

    public init(taskId: Int, description: String, subTypeId: Int, durationInMinutes: Int, completionTime: String) {
        self.taskId = taskId
        self.description = description
        self.subTypeId = subTypeId
        self.durationInMinutes = durationInMinutes
        self.completionTime = completionTime
    }
}

/// `AttachmentResponse` from `GET api/tasks/attachments/{taskId}`.
public struct TaskAttachmentResponse: Decodable, Sendable, Hashable {
    public var id: Int
    public var file: TaskAttachmentFileResponse?
    public var employeeFileDeleted: Bool?
    /// "caseFile" or "employeeFile": which download route serves it.
    public var fileStorageKind: String?

    public init(
        id: Int,
        file: TaskAttachmentFileResponse?,
        employeeFileDeleted: Bool? = nil,
        fileStorageKind: String? = nil
    ) {
        self.id = id
        self.file = file
        self.employeeFileDeleted = employeeFileDeleted
        self.fileStorageKind = fileStorageKind
    }
}

/// `CaseFileResponse`, the fields read here.
public struct TaskAttachmentFileResponse: Decodable, Sendable, Hashable {
    public var id: String?
    public var fileName: String?
    public var mimeType: String?
    public var size: Int64?
    public var createDate: String?
    public var author: TaskUserResponse?

    public init(
        id: String?,
        fileName: String? = nil,
        mimeType: String? = nil,
        size: Int64? = nil,
        createDate: String? = nil,
        author: TaskUserResponse? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.mimeType = mimeType
        self.size = size
        self.createDate = createDate
        self.author = author
    }

    enum CodingKeys: String, CodingKey { case id, fileName, mimeType, size, createDate, author }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.lenient(LenientID.self, forKey: .id)?.value
        fileName = container.lenient(String.self, forKey: .fileName)
        mimeType = container.lenient(String.self, forKey: .mimeType)
        size = container.lenient(Int64.self, forKey: .size)
        createDate = container.lenient(String.self, forKey: .createDate)
        author = container.lenient(TaskUserResponse.self, forKey: .author)
    }
}
