import Foundation

// Mirrors of the sprout_api task review contract: Submit, Approve and Reject on a task
// (`Controllers/WorkflowController/TaskWorkflowController.cs`), the late-justification steps
// (`Controllers/Compliance/TaskJustificationController.cs`) and the employee closure choice
// (`TaskController` employee-closure-*). Enums travel as their names (JsonStringEnumConverter).

/// `TaskCapabilitiesDto` on `GET api/tasks/{id}`: what the caller may do on this task now.
public struct TaskCapabilitiesResponse: Decodable, Sendable, Hashable {
    public var canSubmit: Bool?
    public var canApprove: Bool?
    public var canApproveAllRemaining: Bool?
    public var remainingApprovalStageCount: Int?
    public var canReject: Bool?
}

/// `WorkflowStepDto`: one approval stage. `status` is `COMPLETED`, `ACTIVE` or `FUTURE`.
public struct WorkflowStepResponse: Decodable, Sendable, Hashable {
    public var stepOrder: Int?
    public var stepRole: String?
    public var status: String?
    public var actualApprover: TaskUserResponse?
}

/// `WorkflowApprovalRequirementsResponse` from `GET api/workflow/task/{id}/approval-requirements`.
public struct ApprovalRequirementsResponse: Decodable, Sendable, Hashable {
    public var approvalMode: String?
    public var willCompleteTask: Bool?
    /// A literal date (`DateOnly`): the Drive section a reopened task was filed in before.
    public var previousDriveFilingDate: String?
    public var requirementsVersion: String?
    public var workflowVersion: String?
    public var canApproveAllRemaining: Bool?
    public var remainingStageCount: Int?
    public var requirements: [WorkflowRequirementResponse]?
}

/// `WorkflowTransitionRequirementDto`: information a stage needs before it can be approved.
public struct WorkflowRequirementResponse: Decodable, Sendable, Hashable {
    public var actionId: Int?
    public var requirementKey: String?
    public var actionType: String?
    public var title: String?
    public var description: String?
    public var fields: [WorkflowFieldResponse]?
}

/// `WorkflowTransitionFieldDto`. Today the server only sends `date` fields.
public struct WorkflowFieldResponse: Decodable, Sendable, Hashable {
    public var key: String?
    public var label: String?
    public var fieldType: String?
    public var required: Bool?
    public var defaultValue: String?
}

/// `ApproveTaskStageRequest` for `POST api/workflow/approve/{id}`.
public struct ApproveTaskStageBody: Encodable, Sendable, Equatable {
    public var mode: String
    public var expectedWorkflowVersion: String?
    public var idempotencyKey: String
    public var requirementsVersion: String?
    public var requirementResponses: [RequirementAnswerBody]
    public var acknowledgeRelationshipWarnings: Bool
    public var closeUnfinalizedDrafts: Bool
    public var useOriginalDriveSection: Bool
    public var expectedPreviousDriveFilingDate: String?

    public init(
        mode: String,
        expectedWorkflowVersion: String?,
        idempotencyKey: String,
        requirementsVersion: String?,
        requirementResponses: [RequirementAnswerBody],
        acknowledgeRelationshipWarnings: Bool,
        closeUnfinalizedDrafts: Bool,
        useOriginalDriveSection: Bool,
        expectedPreviousDriveFilingDate: String?
    ) {
        self.mode = mode
        self.expectedWorkflowVersion = expectedWorkflowVersion
        self.idempotencyKey = idempotencyKey
        self.requirementsVersion = requirementsVersion
        self.requirementResponses = requirementResponses
        self.acknowledgeRelationshipWarnings = acknowledgeRelationshipWarnings
        self.closeUnfinalizedDrafts = closeUnfinalizedDrafts
        self.useOriginalDriveSection = useOriginalDriveSection
        self.expectedPreviousDriveFilingDate = expectedPreviousDriveFilingDate
    }
}

/// `WorkflowTransitionRequirementResponse`: the answers to one requirement, keyed by field.
public struct RequirementAnswerBody: Encodable, Sendable, Equatable {
    public var actionId: Int
    public var requirementKey: String
    public var values: [String: String]

    public init(actionId: Int, requirementKey: String, values: [String: String]) {
        self.actionId = actionId
        self.requirementKey = requirementKey
        self.values = values
    }
}

/// `WorkflowApprovalResult`.
public struct ApprovalResultResponse: Decodable, Sendable, Hashable {
    public var taskCompleted: Bool?
}

/// The 409/422 body of an approval the server refused: `code` says why
/// (TASK_COMPLETION_BLOCKED, TASK_COMPLETION_WARNING_REQUIRED, WORKFLOW_REQUIREMENTS_CHANGED, ...).
/// Its message is never shown.
public struct ApprovalErrorResponse: Decodable, Sendable, Hashable {
    public var code: String?
    public var completion: CompletionEvaluationResponse?
    public var requirementsVersion: String?
    public var requirements: [WorkflowRequirementResponse]?
}

/// `TaskCompletionEvaluation`: the related tasks that hold this one up.
public struct CompletionEvaluationResponse: Decodable, Sendable, Hashable {
    public var blockers: [CompletionDependencyResponse]?
    public var warnings: [CompletionDependencyResponse]?
}

/// `TaskCompletionDependency`: one related task and how it relates.
public struct CompletionDependencyResponse: Decodable, Sendable, Hashable {
    public var sourceTaskId: Int?
    public var sourceTaskFriendlyId: Int?
    public var sourceTaskTitle: String?
    public var sourceTaskStatus: String?
    public var organizationAbbreviation: String?
    public var relationshipName: String?
    public var sourceToTargetName: String?
}

/// `RejectOptionDto` from `GET api/workflow/task/{id}/reject-options`: a step the task can go back to.
public struct RejectOptionResponse: Decodable, Sendable, Hashable {
    public var taskApprovalId: Int?
    public var displayName: String?
    public var roleName: String?
}

/// `FeedbackRequest` for `POST api/workflow/reject/{id}`.
public struct RejectTaskBody: Encodable, Sendable, Equatable {
    public var feedback: String
    public var taskApprovalId: Int
    public var durationInMinutes: Int
    public var lateJustificationAdjustmentId: Int64?
    public var lateJustificationDecision: String?

    public init(
        feedback: String,
        taskApprovalId: Int,
        durationInMinutes: Int,
        lateJustificationAdjustmentId: Int64?,
        lateJustificationDecision: String?
    ) {
        self.feedback = feedback
        self.taskApprovalId = taskApprovalId
        self.durationInMinutes = durationInMinutes
        self.lateJustificationAdjustmentId = lateJustificationAdjustmentId
        self.lateJustificationDecision = lateJustificationDecision
    }
}

/// `GET api/form/v2/task/{id}/drafts`: forms with saved progress that isn't finalized.
public struct TaskFormDraftResponse: Decodable, Sendable, Hashable {
    public var id: Int?
    public var formName: String?
}

/// `EmployeeTaskClosureOptionsResponse`.
public struct EmployeeClosureOptionsResponse: Decodable, Sendable, Hashable {
    public var requiresNextExpirationDate: Bool?
    /// A literal date (`DateOnly`).
    public var nextExpirationDate: String?
    public var canMerge: Bool?
    public var eligiblePdfs: [EmployeeClosureFileResponse]?
}

public struct EmployeeClosureFileResponse: Decodable, Sendable, Hashable {
    public var employeeFileId: String?
    public var fileName: String?
    public var size: Int64?

    enum CodingKeys: String, CodingKey { case employeeFileId, fileName, size }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        employeeFileId = container.lenient(LenientID.self, forKey: .employeeFileId)?.value
        fileName = container.lenient(String.self, forKey: .fileName)
        size = container.lenient(Int64.self, forKey: .size)
    }
}

/// `EmployeeTaskClosureRequest` for `PUT api/tasks/{id}/employee-closure-choice`.
public struct EmployeeClosureBody: Encodable, Sendable, Equatable {
    public var mode: String
    public var idempotencyKey: String
    public var orderedEmployeeFileIds: [String]
    public var nextExpirationDate: String?

    public init(mode: String, idempotencyKey: String, orderedEmployeeFileIds: [String], nextExpirationDate: String?) {
        self.mode = mode
        self.idempotencyKey = idempotencyKey
        self.orderedEmployeeFileIds = orderedEmployeeFileIds
        self.nextExpirationDate = nextExpirationDate
    }
}

/// `LateJustificationContextResponse` from `GET api/tasks/{id}/justifications/context`.
public struct LateContextResponse: Decodable, Sendable, Hashable {
    public var isLate: Bool?
    public var canSubmit: Bool?
    public var canReview: Bool?
    public var hasCurrentUserReviewed: Bool?
    public var satisfiesSubmission: Bool?
    public var justification: LateJustificationResponse?
    public var suggestedDelay: LateDelayResponse?
    public var reviews: [LateReviewResponse]?
}

public struct LateJustificationResponse: Decodable, Sendable, Hashable {
    public var id: Int64?
    public var reasonCodeId: Int64?
    public var reasonName: String?
    public var explanation: String?
    public var evidenceAttachmentId: Int?
    public var sourceTaskDelayId: Int64?
    public var submittedByName: String?
    /// `Pending`, `Approved`, `Rejected`, `NotRequired` or `Superseded`.
    public var status: String?
}

public struct LateDelayResponse: Decodable, Sendable, Hashable {
    public var id: Int64?
    public var reasonCodeId: Int64?
    public var reasonName: String?
    public var explanation: String?
    public var evidenceAttachmentId: Int?
}

public struct LateReviewResponse: Decodable, Sendable, Hashable {
    public var reviewerName: String?
    public var reviewerRole: String?
    /// `Agree` or `ReturnForClarification`.
    public var decision: String?
    public var note: String?
}

/// `TaskJustificationRequestDto` for `POST api/tasks/{id}/justifications`.
public struct LateJustificationBody: Encodable, Sendable, Equatable {
    public var reasonCodeId: Int64
    public var explanation: String
    public var evidenceAttachmentId: Int?
    public var sourceTaskDelayId: Int64?

    public init(reasonCodeId: Int64, explanation: String, evidenceAttachmentId: Int?, sourceTaskDelayId: Int64?) {
        self.reasonCodeId = reasonCodeId
        self.explanation = explanation
        self.evidenceAttachmentId = evidenceAttachmentId
        self.sourceTaskDelayId = sourceTaskDelayId
    }
}

/// `LateJustificationReviewRequestDto` for `POST api/tasks/{id}/justifications/{adjustmentId}/reviews`.
public struct LateReviewBody: Encodable, Sendable, Equatable {
    public var decision: String
    public var note: String?
    public var reasonCodeId: Int64?
    public var explanation: String?
    public var evidenceAttachmentId: Int?

    public init(
        decision: String,
        note: String?,
        reasonCodeId: Int64?,
        explanation: String?,
        evidenceAttachmentId: Int?
    ) {
        self.decision = decision
        self.note = note
        self.reasonCodeId = reasonCodeId
        self.explanation = explanation
        self.evidenceAttachmentId = evidenceAttachmentId
    }
}

/// `POST api/file/upload-compliance-evidence` answers `{ attachmentId, fileId }`.
public struct EvidenceUploadResponse: Decodable, Sendable, Hashable {
    public var attachmentId: Int?
}
