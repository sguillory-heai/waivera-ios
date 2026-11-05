import Foundation
import WaiveraAPI

/// What the viewer may do on a task's approval workflow now, straight from the server's
/// capabilities (sprout_api `TaskCapabilityPolicy`). `ready` is `isTaskReady`: every required
/// form, file and signature is done, which Submit and Approve need and Reject does not.
public struct TaskReviewAccess: Sendable, Hashable {
    public var canSubmit: Bool
    public var canApprove: Bool
    public var canApproveAll: Bool
    public var remainingStages: Int
    public var canReject: Bool
    public var ready: Bool

    public init(
        canSubmit: Bool = false,
        canApprove: Bool = false,
        canApproveAll: Bool = false,
        remainingStages: Int = 0,
        canReject: Bool = false,
        ready: Bool = false
    ) {
        self.canSubmit = canSubmit
        self.canApprove = canApprove
        self.canApproveAll = canApproveAll
        self.remainingStages = remainingStages
        self.canReject = canReject
        self.ready = ready
    }

    public static let none = TaskReviewAccess()

    public var any: Bool { canSubmit || canApprove || canReject }
}

public enum StepStatus: Sendable, Hashable { case completed, active, future, unknown }

/// One approval stage, in order. `approverName` is who approved a completed stage.
public struct WorkflowStep: Sendable, Hashable {
    public var order: Int
    public var role: String?
    public var status: StepStatus
    public var approverName: String?

    public init(order: Int, role: String?, status: StepStatus, approverName: String?) {
        self.order = order
        self.role = role
        self.status = status
        self.approverName = approverName
    }
}

/// The participant's plan (CPOC) dates, which a stage that updates them checks new dates against.
public struct PlanDates: Sendable, Hashable {
    public var start: CalendarDate?
    public var end: CalendarDate?

    public init(start: CalendarDate?, end: CalendarDate?) {
        self.start = start
        self.end = end
    }
}

public enum ApprovalMode: String, Sendable, Hashable {
    case currentStage = "CurrentStage"
    case allRemaining = "AllRemaining"
}

public enum RequirementFieldType: Sendable, Hashable { case date, text, longText, number, unsupported }

public struct RequirementField: Sendable, Hashable {
    public var key: String
    public var label: String
    public var type: RequirementFieldType
    public var required: Bool
    public var defaultValue: String?

    public init(key: String, label: String, type: RequirementFieldType, required: Bool, defaultValue: String?) {
        self.key = key
        self.label = label
        self.type = type
        self.required = required
        self.defaultValue = defaultValue
    }
}

/// Information a stage asks for before it can be approved, such as new plan dates.
public struct StageRequirement: Sendable, Hashable {
    public static let planDates = "participant_profile_change"
    public static let planStart = "cpocDate"
    public static let planEnd = "cpocEndDate"

    public var actionId: Int
    public var key: String
    public var actionType: String
    public var title: String
    public var description: String?
    public var fields: [RequirementField]

    public init(
        actionId: Int,
        key: String,
        actionType: String,
        title: String,
        description: String?,
        fields: [RequirementField]
    ) {
        self.actionId = actionId
        self.key = key
        self.actionType = actionType
        self.title = title
        self.description = description
        self.fields = fields
    }

    /// The web turns these away too (file fields are JSON-only on the server).
    public var supported: Bool { !fields.contains { $0.type == .unsupported } }

    /// `participant_profile_change`: new CPOC dates, checked against the current ones.
    public var isPlanDates: Bool { actionType.caseInsensitiveCompare(Self.planDates) == .orderedSame }
}

/// The server's plan for an approval: what it will do and what it needs first.
public struct ApprovalPlan: Sendable, Hashable {
    public var mode: ApprovalMode
    public var willComplete: Bool
    /// A reopened task was filed in this month's Drive section before.
    public var previousFiling: CalendarDate?
    public var requirementsVersion: String?
    public var workflowVersion: String?
    public var canApproveAll: Bool
    public var remainingStages: Int
    public var requirements: [StageRequirement]

    public init(
        mode: ApprovalMode,
        willComplete: Bool,
        previousFiling: CalendarDate? = nil,
        requirementsVersion: String? = nil,
        workflowVersion: String? = nil,
        canApproveAll: Bool = false,
        remainingStages: Int = 1,
        requirements: [StageRequirement] = []
    ) {
        self.mode = mode
        self.willComplete = willComplete
        self.previousFiling = previousFiling
        self.requirementsVersion = requirementsVersion
        self.workflowVersion = workflowVersion
        self.canApproveAll = canApproveAll
        self.remainingStages = remainingStages
        self.requirements = requirements
    }
}

/// One approval send. `answers` maps a requirement's action id to its field values (ISO dates).
public struct ApprovalSend: Sendable, Hashable {
    public var plan: ApprovalPlan
    public var idempotencyKey: String
    public var answers: [Int: [String: String]]
    public var acknowledgeWarnings: Bool
    public var discardDrafts: Bool
    public var useOriginalSection: Bool

    public init(
        plan: ApprovalPlan,
        idempotencyKey: String,
        answers: [Int: [String: String]] = [:],
        acknowledgeWarnings: Bool = false,
        discardDrafts: Bool = false,
        useOriginalSection: Bool = false
    ) {
        self.plan = plan
        self.idempotencyKey = idempotencyKey
        self.answers = answers
        self.acknowledgeWarnings = acknowledgeWarnings
        self.discardDrafts = discardDrafts
        self.useOriginalSection = useOriginalSection
    }
}

/// A related task that holds this one up. `statusName` is the server's status name.
public struct RelatedTask: Sendable, Hashable, Identifiable {
    public var id: Int
    public var key: String
    public var title: String
    public var statusName: String?
    public var relationship: String?

    public init(id: Int, key: String, title: String, statusName: String?, relationship: String?) {
        self.id = id
        self.key = key
        self.title = title
        self.statusName = statusName
        self.relationship = relationship
    }
}

public enum ApprovalOutcome: Sendable, Hashable {
    case approved(completed: Bool)
    /// A related task must be finished first.
    case blocked([RelatedTask])
    /// A related task isn't finished; sending again with acknowledgement completes anyway.
    case needsAcknowledgement([RelatedTask])
    /// The stage's requirements changed or weren't met; these are the current ones.
    case requirementsChanged([StageRequirement], version: String?)
    /// The workflow moved on (someone else acted, or the Drive section is gone): reload.
    case stale
}

/// An earlier step a rejected task can go back to.
public struct SendBackOption: Sendable, Hashable, Identifiable {
    public var approvalId: Int
    public var name: String
    public var role: String?

    public init(approvalId: Int, name: String, role: String?) {
        self.approvalId = approvalId
        self.name = name
        self.role = role
    }

    public var id: Int { approvalId }
}

/// A form with saved progress that completing the task discards.
public struct FormDraft: Sendable, Hashable {
    public var id: Int
    public var name: String

    public init(id: Int, name: String) {
        self.id = id
        self.name = name
    }
}

/// sprout_web `getEmployeeClosureOptions`: how an employee task's files are finalized.
public struct EmployeeClosure: Sendable, Hashable {
    public var needsExpiration: Bool
    public var nextExpiration: CalendarDate?
    public var canMerge: Bool
    public var pdfs: [ClosurePdf]

    public init(needsExpiration: Bool, nextExpiration: CalendarDate?, canMerge: Bool, pdfs: [ClosurePdf]) {
        self.needsExpiration = needsExpiration
        self.nextExpiration = nextExpiration
        self.canMerge = canMerge
        self.pdfs = pdfs
    }

    public var asks: Bool { canMerge || needsExpiration }
}

public struct ClosurePdf: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var sizeBytes: Int64

    public init(id: String, name: String, sizeBytes: Int64) {
        self.id = id
        self.name = name
        self.sizeBytes = sizeBytes
    }
}

/// sprout_api `LateJustificationContextResponse`: where a late task's reason stands for the viewer.
public struct LateContext: Sendable, Hashable {
    /// The server's own lateness (UTC days); the phone asks for a reason only when this is true.
    public var late: Bool
    public var canSubmit: Bool
    public var canReview: Bool
    public var reviewedByMe: Bool
    public var satisfied: Bool
    public var justification: LateJustification?
    public var suggestedDelay: SuggestedDelay?
    public var reviews: [LateReview]

    public init(
        late: Bool = true,
        canSubmit: Bool,
        canReview: Bool,
        reviewedByMe: Bool,
        satisfied: Bool,
        justification: LateJustification? = nil,
        suggestedDelay: SuggestedDelay? = nil,
        reviews: [LateReview] = []
    ) {
        self.late = late
        self.canSubmit = canSubmit
        self.canReview = canReview
        self.reviewedByMe = reviewedByMe
        self.satisfied = satisfied
        self.justification = justification
        self.suggestedDelay = suggestedDelay
        self.reviews = reviews
    }

    /// Returned for correction: its values come back so they can be fixed, not retyped.
    public var returned: Bool { justification?.returned == true }

    /// The latest reviewer's correction note, for a returned reason.
    public var correction: String? {
        guard returned else { return nil }
        return reviews.last { !$0.agreed && !($0.note ?? "").trimmingCharacters(in: .whitespaces).isEmpty }?.note
    }
}

public struct LateJustification: Sendable, Hashable {
    public var id: Int64
    public var reasonId: Int64
    public var reasonName: String?
    public var explanation: String
    public var evidenceId: Int?
    public var delayId: Int64?
    public var submittedBy: String?
    public var returned: Bool

    public init(
        id: Int64,
        reasonId: Int64,
        reasonName: String?,
        explanation: String,
        evidenceId: Int? = nil,
        delayId: Int64? = nil,
        submittedBy: String? = nil,
        returned: Bool = false
    ) {
        self.id = id
        self.reasonId = reasonId
        self.reasonName = reasonName
        self.explanation = explanation
        self.evidenceId = evidenceId
        self.delayId = delayId
        self.submittedBy = submittedBy
        self.returned = returned
    }
}

/// A reported delay whose reason can stand in for the late reason.
public struct SuggestedDelay: Sendable, Hashable {
    public var id: Int64
    public var reasonId: Int64
    public var reasonName: String?
    public var explanation: String
    public var evidenceId: Int?

    public init(id: Int64, reasonId: Int64, reasonName: String?, explanation: String, evidenceId: Int? = nil) {
        self.id = id
        self.reasonId = reasonId
        self.reasonName = reasonName
        self.explanation = explanation
        self.evidenceId = evidenceId
    }
}

public struct LateReview: Sendable, Hashable {
    public var name: String?
    public var role: String?
    public var agreed: Bool
    public var note: String?

    public init(name: String?, role: String?, agreed: Bool, note: String?) {
        self.name = name
        self.role = role
        self.agreed = agreed
        self.note = note
    }
}

/// A reviewer's own correction of the late reason, saved as they agree with it.
public struct LateEdit: Sendable, Hashable {
    public var reasonId: Int64
    public var explanation: String
    public var evidenceId: Int?

    public init(reasonId: Int64, explanation: String, evidenceId: Int?) {
        self.reasonId = reasonId
        self.explanation = explanation
        self.evidenceId = evidenceId
    }
}
