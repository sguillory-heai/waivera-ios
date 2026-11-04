import Foundation
import WaiveraAPI

/// What a change request asks for, by the server's request type name.
public enum RequestKind: String, Sendable, Hashable, Codable {
    /// "Task Extension Request": a later due date.
    case moreTime
    /// "Task Delay Request": known lateness is recorded; the due date stays.
    case delay
    /// "Task Deletion Request": the task closes without being completed.
    case closure
    /// Time off, profile changes, reactivations and anything newer: reviewed on the web.
    case other

    public init(typeName: String?) {
        switch typeName?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "task extension request": self = .moreTime
        case "task delay request": self = .delay
        case "task deletion request": self = .closure
        default: self = .other
        }
    }

    /// The phone reviews only the task requests the web reviews with approve and reject alone.
    public var reviewableHere: Bool { self != .other }
}

public enum RequestStatus: String, Sendable, Hashable, Codable {
    case pending
    case approved
    case rejected
    case other

    public init(name: String?) {
        switch name?.trimmingCharacters(in: .whitespaces).uppercased() {
        case "PENDING": self = .pending
        case "APPROVED": self = .approved
        case "REJECTED", "DECLINED": self = .rejected
        default: self = .other
        }
    }
}

/// One change request. The dates it moves are literal calendar dates; `requestedAt` and
/// `decidedAt` are UTC instants.
public struct ChangeRequest: Sendable, Hashable, Identifiable {
    public var id: Int
    public var kind: RequestKind
    /// The server's type name, shown for kinds the phone does not review.
    public var typeName: String
    public var status: RequestStatus
    public var requesterId: String?
    public var requesterName: String
    public var approverName: String?
    public var requestedAt: Date?
    public var decidedAt: Date?
    public var taskId: Int?
    public var taskTitle: String?
    /// The picked explanation code (more time, delay) or closure reason.
    public var reason: String?
    /// What the requester wrote.
    public var explanation: String?
    public var currentDue: CalendarDate?
    public var requestedDue: CalendarDate?
    public var delayStart: CalendarDate?
    public var delayEnd: CalendarDate?
    public var isTrainingTask: Bool

    public init(
        id: Int,
        kind: RequestKind,
        typeName: String,
        status: RequestStatus,
        requesterId: String?,
        requesterName: String,
        approverName: String? = nil,
        requestedAt: Date? = nil,
        decidedAt: Date? = nil,
        taskId: Int? = nil,
        taskTitle: String? = nil,
        reason: String? = nil,
        explanation: String? = nil,
        currentDue: CalendarDate? = nil,
        requestedDue: CalendarDate? = nil,
        delayStart: CalendarDate? = nil,
        delayEnd: CalendarDate? = nil,
        isTrainingTask: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.typeName = typeName
        self.status = status
        self.requesterId = requesterId
        self.requesterName = requesterName
        self.approverName = approverName
        self.requestedAt = requestedAt
        self.decidedAt = decidedAt
        self.taskId = taskId
        self.taskTitle = taskTitle
        self.reason = reason
        self.explanation = explanation
        self.currentDue = currentDue
        self.requestedDue = requestedDue
        self.delayStart = delayStart
        self.delayEnd = delayEnd
        self.isTrainingTask = isTrainingTask
    }
}

/// What the person may ask for on one task, from the server's eligibility check.
public struct ChangeOptions: Sendable, Hashable {
    public var taskId: Int
    public var currentDue: CalendarDate?
    public var canAskMoreTime: Bool
    /// The server-owned delay period; nil when a delay cannot be reported now.
    public var delay: DelayPeriod?
    public var hasPendingRequest: Bool

    public init(
        taskId: Int,
        currentDue: CalendarDate?,
        canAskMoreTime: Bool,
        delay: DelayPeriod?,
        hasPendingRequest: Bool
    ) {
        self.taskId = taskId
        self.currentDue = currentDue
        self.canAskMoreTime = canAskMoreTime
        self.delay = delay
        self.hasPendingRequest = hasPendingRequest
    }
}

public struct DelayPeriod: Sendable, Hashable {
    public var start: CalendarDate
    public var end: CalendarDate
    public var renewal: Bool

    public init(start: CalendarDate, end: CalendarDate, renewal: Bool) {
        self.start = start
        self.end = end
        self.renewal = renewal
    }
}

/// A reason the person picks from. `requiresEvidence` needs a file already on the task.
public struct ChangeReason: Sendable, Hashable, Identifiable {
    public var id: Int64
    public var name: String
    public var description: String?
    public var requiresEvidence: Bool
    /// Closure reasons named "Other" need a comment, as on the web.
    public var needsComment: Bool

    public init(id: Int64, name: String, description: String?, requiresEvidence: Bool, needsComment: Bool = false) {
        self.id = id
        self.name = name
        self.description = description
        self.requiresEvidence = requiresEvidence
        self.needsComment = needsComment
    }
}

/// A file attached to the task that a request can cite as evidence.
public struct TaskFileRef: Sendable, Hashable, Identifiable {
    public var attachmentId: Int
    public var name: String
    public var id: Int { attachmentId }

    public init(attachmentId: Int, name: String) {
        self.attachmentId = attachmentId
        self.name = name
    }
}

/// Whether an asked change took effect at once (an owner's own request) or waits for review.
public enum RequestOutcome: Sendable, Hashable {
    case approved
    case pending
}

/// What the person may see and do with change requests, from the same role policies the web
/// checks. The server re-checks every action; these only decide what is offered.
public struct RequestAccess: Sendable, Hashable {
    public var canAskMoreTime: Bool
    public var canAskClosure: Bool
    /// The Requests list, under the web's Admin Requests rule.
    public var showsRequests: Bool
    /// Whether casework includes tasks waiting for approval, as the web's task list does.
    public var includePendingApprovals: Bool
    public var loaded: Bool

    public init(
        canAskMoreTime: Bool = false,
        canAskClosure: Bool = false,
        showsRequests: Bool = false,
        includePendingApprovals: Bool = false,
        loaded: Bool = false
    ) {
        self.canAskMoreTime = canAskMoreTime
        self.canAskClosure = canAskClosure
        self.showsRequests = showsRequests
        self.includePendingApprovals = includePendingApprovals
        self.loaded = loaded
    }
}
