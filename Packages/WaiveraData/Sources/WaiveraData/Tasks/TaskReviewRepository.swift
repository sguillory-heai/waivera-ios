import Foundation
import WaiveraAPI

/// Submitting, approving and rejecting a task, and every step the web runs on the way
/// (sprout_web `TaskPage.HandleApprove`). The server re-checks each call against the viewer's
/// own workflow role, so a stale screen fails safely.
public protocol TaskReviewRepository: Sendable {
    func plan(taskId: Int, mode: ApprovalMode) async throws -> ApprovalPlan
    /// A refusal the person can act on is an `ApprovalOutcome`; anything else throws.
    func approve(taskId: Int, send: ApprovalSend) async throws -> ApprovalOutcome
    func drafts(taskId: Int) async throws -> [FormDraft]
    func employeeClosure(taskId: Int) async throws -> EmployeeClosure
    /// `merge` lists the PDFs to combine, in order; nil closes and finalizes each file.
    func chooseClosure(taskId: Int, merge: [String]?, nextExpiration: CalendarDate?) async throws
    /// Empty when there is no earlier step.
    func sendBackOptions(taskId: Int) async throws -> [SendBackOption]
    /// `lateReasonId` when it returns a late reason for correction.
    func sendBack(taskId: Int, option: SendBackOption, feedback: String, minutes: Int, lateReasonId: Int64?)
        async throws
    func lateContext(taskId: Int) async throws -> LateContext
    /// Reasons that may explain a late task.
    func lateReasons() async throws -> [ChangeReason]
    func justify(taskId: Int, reasonId: Int64, explanation: String, evidenceId: Int?, delayId: Int64?) async throws
    /// Agrees with a late reason, optionally correcting it first.
    func agreeLate(taskId: Int, justificationId: Int64, note: String?, edit: LateEdit?) async throws
}

/// The same endpoints, in the same order, as sprout_web.
public struct LiveTaskReviewRepository: TaskReviewRepository {
    private let api: APIClient

    public init(api: APIClient) { self.api = api }

    public func plan(taskId: Int, mode: ApprovalMode) async throws -> ApprovalPlan {
        ReviewMapping.plan(try await api.approvalRequirements(taskId: taskId, mode: mode.rawValue), asked: mode)
    }

    public func approve(taskId: Int, send: ApprovalSend) async throws -> ApprovalOutcome {
        switch try await api.approve(taskId: taskId, ReviewMapping.body(send)) {
        case .approved(let completed): .approved(completed: completed)
        case .refused(let body): ReviewMapping.refusal(body)
        }
    }

    public func drafts(taskId: Int) async throws -> [FormDraft] {
        ReviewMapping.drafts(try await api.formDrafts(taskId: taskId))
    }

    public func employeeClosure(taskId: Int) async throws -> EmployeeClosure {
        ReviewMapping.closure(try await api.employeeClosureOptions(taskId: taskId))
    }

    public func chooseClosure(taskId: Int, merge: [String]?, nextExpiration: CalendarDate?) async throws {
        try await api.employeeClosureChoice(
            taskId: taskId,
            EmployeeClosureBody(
                mode: merge == nil ? ReviewMapping.close : ReviewMapping.merge,
                idempotencyKey: "employee-close-\(taskId)-\(UUID().uuidString.lowercased())",
                orderedEmployeeFileIds: merge ?? [],
                nextExpirationDate: nextExpiration?.isoString
            )
        )
    }

    public func sendBackOptions(taskId: Int) async throws -> [SendBackOption] {
        do {
            return ReviewMapping.options(try await api.rejectOptions(taskId: taskId))
        } catch WaiveraError.notFound {
            // The server answers 404 when there is no earlier step, as the web reads it.
            return []
        }
    }

    public func sendBack(
        taskId: Int,
        option: SendBackOption,
        feedback: String,
        minutes: Int,
        lateReasonId: Int64?
    ) async throws {
        try await api.reject(
            taskId: taskId,
            RejectTaskBody(
                feedback: feedback,
                taskApprovalId: option.approvalId,
                durationInMinutes: minutes,
                lateJustificationAdjustmentId: lateReasonId,
                lateJustificationDecision: lateReasonId == nil ? nil : ReviewMapping.returnDecision
            )
        )
    }

    public func lateContext(taskId: Int) async throws -> LateContext {
        ReviewMapping.late(try await api.lateContext(taskId: taskId))
    }

    public func lateReasons() async throws -> [ChangeReason] {
        ReviewMapping.lateReasons(try await api.complianceReasons())
    }

    public func justify(
        taskId: Int,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?,
        delayId: Int64?
    ) async throws {
        try await api.justify(
            taskId: taskId,
            LateJustificationBody(
                reasonCodeId: reasonId,
                explanation: explanation,
                evidenceAttachmentId: evidenceId,
                sourceTaskDelayId: delayId
            )
        )
    }

    public func agreeLate(taskId: Int, justificationId: Int64, note: String?, edit: LateEdit?) async throws {
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await api.reviewJustification(
            taskId: taskId,
            adjustmentId: justificationId,
            LateReviewBody(
                decision: ReviewMapping.agree,
                note: (trimmed?.isEmpty ?? true) ? nil : trimmed,
                reasonCodeId: edit?.reasonId,
                explanation: edit?.explanation,
                evidenceAttachmentId: edit?.evidenceId
            )
        )
    }
}

/// No review: for previews and environments that have no task server.
public struct EmptyTaskReviewRepository: TaskReviewRepository {
    public init() {}

    public func plan(taskId: Int, mode: ApprovalMode) async throws -> ApprovalPlan { throw WaiveraError.notFound }
    public func approve(taskId: Int, send: ApprovalSend) async throws -> ApprovalOutcome {
        throw WaiveraError.notFound
    }
    public func drafts(taskId: Int) async throws -> [FormDraft] { [] }
    public func employeeClosure(taskId: Int) async throws -> EmployeeClosure { throw WaiveraError.notFound }
    public func chooseClosure(taskId: Int, merge: [String]?, nextExpiration: CalendarDate?) async throws {
        throw WaiveraError.notFound
    }
    public func sendBackOptions(taskId: Int) async throws -> [SendBackOption] { [] }
    public func sendBack(
        taskId: Int,
        option: SendBackOption,
        feedback: String,
        minutes: Int,
        lateReasonId: Int64?
    ) async throws { throw WaiveraError.notFound }
    public func lateContext(taskId: Int) async throws -> LateContext { throw WaiveraError.notFound }
    public func lateReasons() async throws -> [ChangeReason] { [] }
    public func justify(
        taskId: Int,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?,
        delayId: Int64?
    ) async throws { throw WaiveraError.notFound }
    public func agreeLate(taskId: Int, justificationId: Int64, note: String?, edit: LateEdit?) async throws {
        throw WaiveraError.notFound
    }
}
