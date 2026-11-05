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
    /// "Time-Off Request".
    case timeOff
    /// "Time-Off Cancellation": approved time off handed back.
    case timeOffCancellation
    /// "Profile Change Request": new details for a participant.
    case profileChange
    /// "Task Reactivation": a closed task opens again.
    case reactivation
    /// "Required Attachment Removal Request": a required file is no longer needed.
    case attachmentRemoval
    /// "External Training Credit": a certificate from training outside Waivera.
    case trainingCredit
    /// Anything newer than this app: reviewed on the web.
    case other

    public init(typeName: String?) {
        switch typeName?.trimmingCharacters(in: .whitespaces).lowercased() {
        case "task extension request": self = .moreTime
        case "task delay request": self = .delay
        case "task deletion request": self = .closure
        case "time-off request": self = .timeOff
        case "time-off cancellation": self = .timeOffCancellation
        case "profile change request": self = .profileChange
        case "task reactivation": self = .reactivation
        case "required attachment removal request": self = .attachmentRemoval
        case "external training credit": self = .trainingCredit
        default: self = .other
        }
    }

    /// Every kind the server's approval inbox returns is reviewed on the phone, as on the web.
    public var reviewableHere: Bool { self != .other }

    public var isTimeOff: Bool { self == .timeOff || self == .timeOffCancellation }
}

/// The time off a request asks for or hands back. Full days are literal dates; a partial day is
/// a pair of instants told in the agency's leave zone.
public struct TimeOffReview: Sendable, Hashable {
    public var leaveType: String
    public var leaveTypeId: Int
    public var partialDay: Bool
    public var startDate: CalendarDate?
    public var endDate: CalendarDate?
    public var start: Date?
    public var end: Date?
    public var minutes: Int
    public var note: String?
    /// The task review saved with the request, refreshed by the server when it can.
    public var impact: LeaveImpact?
    public var impactChanged: Bool
    /// Nil when the request carries no task review at all.
    public var acknowledged: Bool?

    public init(
        leaveType: String, leaveTypeId: Int, partialDay: Bool, startDate: CalendarDate?, endDate: CalendarDate?,
        start: Date?, end: Date?, minutes: Int, note: String?, impact: LeaveImpact?, impactChanged: Bool,
        acknowledged: Bool?
    ) {
        self.leaveType = leaveType
        self.leaveTypeId = leaveTypeId
        self.partialDay = partialDay
        self.startDate = startDate
        self.endDate = endDate
        self.start = start
        self.end = end
        self.minutes = minutes
        self.note = note
        self.impact = impact
        self.impactChanged = impactChanged
        self.acknowledged = acknowledged
    }
}

/// sprout_web `LeaveImpactSummary`: open tasks due around the leave and the notices that matter.
public struct LeaveImpact: Sendable, Hashable {
    public var dueBefore: Int
    public var dueDuring: Int
    public var shortNotice: Bool
    /// Sick leave over three working days; the agency may ask for documentation.
    public var extendedSick: Bool

    public init(dueBefore: Int, dueDuring: Int, shortNotice: Bool, extendedSick: Bool = false) {
        self.dueBefore = dueBefore
        self.dueDuring = dueDuring
        self.shortNotice = shortNotice
        self.extendedSick = extendedSick
    }
}

/// The employee's balance for one leave type; `tracksBalance` false needs none.
public struct LeaveBalance: Sendable, Hashable {
    public var leaveTypeId: Int
    public var tracksBalance: Bool
    public var availableMinutes: Int

    public init(leaveTypeId: Int, tracksBalance: Bool, availableMinutes: Int) {
        self.leaveTypeId = leaveTypeId
        self.tracksBalance = tracksBalance
        self.availableMinutes = availableMinutes
    }
}

/// One participant field in a profile change, as the web compares them.
public struct ProfileField: Sendable, Hashable {
    /// The web's order. SSN digits never reach the screen.
    public enum Field: Int, Sendable, Hashable, CaseIterable {
        case dateOfBirth, firstName, lastName, email, mobile, waiver, waiverId, ssn, certification, cpocStart, cpocEnd
    }

    public var field: Field
    /// Text as entered; dates as `YYYY-MM-DD`; SSN digits are already masked.
    public var previous: String?
    public var requested: String?
    public var changed: Bool

    public init(field: Field, previous: String?, requested: String?, changed: Bool) {
        self.field = field
        self.previous = previous
        self.requested = requested
        self.changed = changed
    }
}

public enum TrainingBlock: Sendable, Hashable {
    case ownCredit, noReviewer, notReviewer
}

/// An external training certificate under review (`training/external/requests/{id}`).
public struct TrainingCredit: Sendable, Hashable {
    public var requestId: Int
    public var course: String
    public var employeeName: String
    public var trainer: String?
    public var provider: String?
    public var completed: CalendarDate?
    public var hours: Double
    public var pending: Bool
    /// Needed to decide; a stale one is refused by the server.
    public var revision: Int?
    public var canApprove: Bool
    /// The reviewer uploaded it for the employee, so approving needs a reason too.
    public var needsApproveReason: Bool
    public var uploadedBy: String?
    public var blocked: TrainingBlock?
    /// Reviewed on the web's training page instead.
    public var reviewOnWeb: Bool

    public var decidable: Bool { pending && canApprove && revision != nil && !reviewOnWeb }

    public init(
        requestId: Int, course: String, employeeName: String, trainer: String?, provider: String?,
        completed: CalendarDate?, hours: Double, pending: Bool, revision: Int?, canApprove: Bool,
        needsApproveReason: Bool, uploadedBy: String?, blocked: TrainingBlock?, reviewOnWeb: Bool
    ) {
        self.requestId = requestId
        self.course = course
        self.employeeName = employeeName
        self.trainer = trainer
        self.provider = provider
        self.completed = completed
        self.hours = hours
        self.pending = pending
        self.revision = revision
        self.canApprove = canApprove
        self.needsApproveReason = needsApproveReason
        self.uploadedBy = uploadedBy
        self.blocked = blocked
        self.reviewOnWeb = reviewOnWeb
    }
}

/// What a training decision sends besides yes or no.
public struct TrainingDecision: Sendable, Hashable {
    public var revision: Int
    public var reason: String

    public init(revision: Int, reason: String) {
        self.revision = revision
        self.reason = reason
    }
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
    public var timeOff: TimeOffReview?
    /// Profile changes: every field the web compares, changed first.
    public var profile: [ProfileField]

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
        isTrainingTask: Bool = false,
        timeOff: TimeOffReview? = nil,
        profile: [ProfileField] = []
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
        self.timeOff = timeOff
        self.profile = profile
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
    /// The web's Download permission for case files (participant tasks), `case_file:download`.
    public var canDownloadCaseFiles: Bool
    /// The same for employee files, `employee_file:download`.
    public var canDownloadEmployeeFiles: Bool
    /// Asking for time off, `admin_request:create:time_off`.
    public var canRequestTimeOff: Bool
    public var loaded: Bool

    public init(
        canAskMoreTime: Bool = false,
        canAskClosure: Bool = false,
        showsRequests: Bool = false,
        includePendingApprovals: Bool = false,
        canDownloadCaseFiles: Bool = false,
        canDownloadEmployeeFiles: Bool = false,
        canRequestTimeOff: Bool = false,
        loaded: Bool = false
    ) {
        self.canAskMoreTime = canAskMoreTime
        self.canAskClosure = canAskClosure
        self.showsRequests = showsRequests
        self.includePendingApprovals = includePendingApprovals
        self.canDownloadCaseFiles = canDownloadCaseFiles
        self.canDownloadEmployeeFiles = canDownloadEmployeeFiles
        self.canRequestTimeOff = canRequestTimeOff
        self.loaded = loaded
    }
}
