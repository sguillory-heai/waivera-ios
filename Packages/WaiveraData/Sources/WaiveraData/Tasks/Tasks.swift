import Foundation
import WaiveraAPI

/// Which of the person's open tasks to list. The server judges the dates in the employee's saved
/// zone: `dueSoon` is today through a month out, `overdue` is before today.
public enum TaskWindow: Sendable, Hashable, CaseIterable {
    case dueSoon
    case overdue
    case allOpen

    /// The server's `date` filter; all open tasks need none.
    var dateFilter: [String] {
        switch self {
        case .dueSoon: ["month"]
        case .overdue: ["overdue"]
        case .allOpen: []
        }
    }
}

/// Whose tasks to list. `casework` is the web's client task list, scoped on the server by role
/// (an owner sees the agency, a coordinator their caseload); `mine` is the person's own employee
/// work (training, credentials), as the web's Employee tasks view.
public enum TaskScope: Sendable, Hashable {
    case casework
    case mine
}

/// How casework treats tasks under an approved delay, as the web's Task Delay filter: `show`
/// lists them (in their own group), `hide` leaves them out, `only` lists nothing else. A delay
/// never moves the due date; it only means the task is not really overdue while it lasts.
public enum DelayFilter: Sendable, Hashable, CaseIterable {
    case show
    case hide
    case only

    /// The server's `taskDelayFilter`; `show` sends none.
    var serverValue: String? {
        switch self {
        case .show: nil
        case .hide: "without-delays"
        case .only: "delayed"
        }
    }
}

/// One list request. `assignedToMe` narrows casework to the person's own tasks.
public struct TaskQuery: Sendable, Hashable {
    public var scope: TaskScope
    public var window: TaskWindow
    public var search: String
    public var assignedToMe: Bool
    /// Casework only: the server applies delay filters to client tasks alone.
    public var delays: DelayFilter

    public init(
        scope: TaskScope,
        window: TaskWindow,
        search: String = "",
        assignedToMe: Bool = false,
        delays: DelayFilter = .show
    ) {
        self.scope = scope
        self.window = window
        self.search = search
        self.assignedToMe = assignedToMe
        self.delays = delays
    }
}

/// A task's workflow state, by its server name. Unknown names keep their text.
public enum TaskState: Sendable, Hashable {
    case notStarted
    case inProgress
    case inReview
    case completed
    case closed
    case other(String)

    public init(name: String?) {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        switch trimmed.uppercased() {
        case "NOT STARTED", "OPEN", "NEW", "TO DO": self = .notStarted
        case "IN PROGRESS", "ACTIVE": self = .inProgress
        case "IN REVIEW", "PENDING APPROVAL", "AWAITING APPROVAL": self = .inReview
        case "COMPLETED": self = .completed
        case "CLOSED": self = .closed
        default: self = .other(trimmed)
        }
    }
}

/// One row of the task list: list fields only, nothing else is kept on the phone.
public struct TaskSummary: Sendable, Hashable, Identifiable {
    public var id: Int
    /// The agency's label, as the web shows it: `HEA-1042`.
    public var key: String
    public var title: String
    /// A literal calendar date, never shifted by a zone.
    public var due: CalendarDate?
    public var state: TaskState
    /// Who or what the task is about: a participant or, for employee tasks, an employee.
    public var about: String?
    public var assigneeId: String?
    public var assigneeName: String?
    /// A closure request waits on review.
    public var pendingClosure: Bool
    /// An approved delay covers today, judged in the employee's zone: not really overdue.
    public var delayed: Bool
    /// That delay's last day, when the server sends one.
    public var delayedThrough: CalendarDate?

    public init(
        id: Int,
        key: String,
        title: String,
        due: CalendarDate?,
        state: TaskState,
        about: String?,
        assigneeId: String? = nil,
        assigneeName: String? = nil,
        pendingClosure: Bool = false,
        delayed: Bool = false,
        delayedThrough: CalendarDate? = nil
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.due = due
        self.state = state
        self.about = about
        self.assigneeId = assigneeId
        self.assigneeName = assigneeName
        self.pendingClosure = pendingClosure
        self.delayed = delayed
        self.delayedThrough = delayedThrough
    }
}

public struct TaskPage: Sendable, Hashable {
    public var items: [TaskSummary]
    public var totalCount: Int

    public init(items: [TaskSummary], totalCount: Int) {
        self.items = items
        self.totalCount = totalCount
    }
}

/// `overdue` leaves out delayed tasks, as the web's to-dos do; `delayed` counts those under a delay today.
public struct TaskCounts: Sendable, Hashable {
    public var open: Int
    public var overdue: Int
    public var delayed: Int

    public init(open: Int, overdue: Int, delayed: Int = 0) {
        self.open = open
        self.overdue = overdue
        self.delayed = delayed
    }
}

/// The approved delay covering today. The due date stays as it was.
public struct TaskDelay: Sendable, Hashable {
    public var reason: String?
    public var explanation: String?
    public var start: CalendarDate?
    public var through: CalendarDate?

    public init(reason: String?, explanation: String?, start: CalendarDate?, through: CalendarDate?) {
        self.reason = reason
        self.explanation = explanation
        self.start = start
        self.through = through
    }
}

public struct TaskDetail: Sendable, Hashable, Identifiable {
    public var id: Int
    public var key: String
    public var title: String
    public var description: String?
    public var state: TaskState
    public var type: String?
    public var start: CalendarDate?
    public var due: CalendarDate?
    public var assignedBy: String?
    public var about: String?
    /// The web app's page for the task, relative to the configured web base.
    public var webPath: String
    public var assigneeName: String?
    /// A participant task; employee tasks have no extension or delay requests.
    public var isClientTask: Bool
    /// A change request waiting on review, if any.
    public var pendingRequest: ChangeRequest?
    /// The approved delay covering today, if any.
    public var delay: TaskDelay?
    /// Submit, Approve and Reject, as the server allows them now.
    public var review: TaskReviewAccess
    /// The approval stages in order; empty when the task has no workflow.
    public var steps: [WorkflowStep]
    public var planDates: PlanDates?

    public init(
        id: Int,
        key: String,
        title: String,
        description: String? = nil,
        state: TaskState,
        type: String? = nil,
        start: CalendarDate? = nil,
        due: CalendarDate? = nil,
        assignedBy: String? = nil,
        about: String? = nil,
        webPath: String,
        assigneeName: String? = nil,
        isClientTask: Bool = true,
        pendingRequest: ChangeRequest? = nil,
        delay: TaskDelay? = nil,
        review: TaskReviewAccess = .none,
        steps: [WorkflowStep] = [],
        planDates: PlanDates? = nil
    ) {
        self.id = id
        self.key = key
        self.title = title
        self.description = description
        self.state = state
        self.type = type
        self.start = start
        self.due = due
        self.assignedBy = assignedBy
        self.about = about
        self.webPath = webPath
        self.assigneeName = assigneeName
        self.isClientTask = isClientTask
        self.pendingRequest = pendingRequest
        self.delay = delay
        self.review = review
        self.steps = steps
        self.planDates = planDates
    }

    /// Completed or closed: the server refuses new activity.
    public var isFinished: Bool { state == .completed || state == .closed }
}

/// One logged activity on a task.
public struct TaskActivity: Sendable, Hashable, Identifiable {
    public var id: Int
    public var type: String
    public var minutes: Int
    /// When the work happened, else when it was logged. A UTC instant.
    public var at: Date?
    public var authorId: String?
    public var authorName: String?
    public var description: String?

    public init(
        id: Int,
        type: String,
        minutes: Int,
        at: Date?,
        authorId: String?,
        authorName: String?,
        description: String?
    ) {
        self.id = id
        self.type = type
        self.minutes = minutes
        self.at = at
        self.authorId = authorId
        self.authorName = authorName
        self.description = description
    }
}

/// An activity type the person may log. `fixedDescription` and `recommendedMinutes` lock those
/// fields, as on the web.
public struct ActivityType: Sendable, Hashable, Identifiable {
    public var id: Int
    public var name: String
    public var recommendedMinutes: Int?
    public var fixedDescription: String?
    /// Logging it takes one uploaded file; the server then sets its time to `recommendedMinutes`.
    public var needsFile: Bool
    /// The template that file is saved as, when the organization still has it.
    public var fileTemplate: FileTemplate?

    public init(
        id: Int,
        name: String,
        recommendedMinutes: Int?,
        fixedDescription: String?,
        needsFile: Bool = false,
        fileTemplate: FileTemplate? = nil
    ) {
        self.id = id
        self.name = name
        self.recommendedMinutes = recommendedMinutes
        self.fixedDescription = fixedDescription
        self.needsFile = needsFile
        self.fileTemplate = fileTemplate
    }
}

public struct NewActivity: Sendable, Hashable {
    public var taskId: Int
    public var typeId: Int
    public var minutes: Int
    public var completedAt: Date
    public var description: String

    public init(taskId: Int, typeId: Int, minutes: Int, completedAt: Date, description: String) {
        self.taskId = taskId
        self.typeId = typeId
        self.minutes = minutes
        self.completedAt = completedAt
        self.description = description
    }
}

/// How a task file can be shown on the phone; `other` opens on the web.
public enum FileKind: Sendable, Hashable, CaseIterable {
    case pdf
    case image
    case text
    case word
    case other

    private static let images: Set<String> = ["jpg", "jpeg", "png", "gif", "webp", "bmp", "heic", "heif"]
    private static let texts: Set<String> = ["txt", "text", "log", "md"]

    /// The name's extension decides, as on the web; the type only fills in for a bare name.
    public init(name: String, mimeType: String?) {
        let ext = name.contains(".") ? (name.split(separator: ".").last.map { $0.lowercased() } ?? "") : ""
        let mime = mimeType?.lowercased() ?? ""
        if ext == "pdf" {
            self = .pdf
        } else if Self.images.contains(ext) {
            self = .image
        } else if Self.texts.contains(ext) {
            self = .text
        } else if ext == "docx" {
            self = .word
        } else if !ext.isEmpty {
            self = .other
        } else if mime == "application/pdf" {
            self = .pdf
        } else if mime.hasPrefix("image/") {
            self = .image
        } else if mime == "text/plain" {
            self = .text
        } else if mime == "application/vnd.openxmlformats-officedocument.wordprocessingml.document" {
            self = .word
        } else {
            self = .other
        }
    }
}

/// A file on a task. Opening it reads it on the phone, never saving or sharing it.
public struct TaskAttachment: Sendable, Hashable, Identifiable {
    /// The web previews Word files up to 20 MB; the phone uses the same limit for every type.
    public static let maxViewBytes: Int64 = 20 * 1024 * 1024

    public var attachmentId: Int
    public var fileId: String
    public var name: String
    public var sizeBytes: Int64
    public var addedAt: Date?
    public var addedBy: String?
    /// Served through the employee-file route, checked against the task.
    public var employeeFile: Bool
    public var kind: FileKind

    public var id: Int { attachmentId }

    public init(
        attachmentId: Int,
        fileId: String,
        name: String,
        sizeBytes: Int64,
        addedAt: Date? = nil,
        addedBy: String? = nil,
        employeeFile: Bool = false,
        kind: FileKind
    ) {
        self.attachmentId = attachmentId
        self.fileId = fileId
        self.name = name
        self.sizeBytes = sizeBytes
        self.addedAt = addedAt
        self.addedBy = addedBy
        self.employeeFile = employeeFile
        self.kind = kind
    }

    /// Shown here when the phone can draw it and it is small enough, as the web's preview limit.
    public var viewable: Bool { kind != .other && sizeBytes <= Self.maxViewBytes }
}
