import Foundation
import WaiveraAPI
import WaiveraData

/// The review chain in memory (Android `FakeTaskReview`): tests set each answer and read what
/// was sent. A nil answer fails that call with `failure`.
public final class FakeTaskReviewRepository: TaskReviewRepository, @unchecked Sendable {
    public struct SentBack: Sendable, Hashable {
        public var approvalId: Int
        public var feedback: String
        public var minutes: Int
        public var lateReasonId: Int64?
    }

    public struct Justified: Sendable, Hashable {
        public var reasonId: Int64
        public var explanation: String
        public var evidenceId: Int?
        public var delayId: Int64?
    }

    public struct Agreed: Sendable, Hashable {
        public var justificationId: Int64
        public var note: String?
        public var edit: LateEdit?
    }

    public struct ClosureChoice: Sendable, Hashable {
        public var merge: [String]?
        public var nextExpiration: CalendarDate?
    }

    public let failure = LockedValue<WaiveraError>(.server(statusCode: 503))
    /// The plan for each mode; a missing mode fails.
    public let plans = LockedValue<[ApprovalMode: ApprovalPlan]>([
        .currentStage: FakeTaskReviewRepository.plan(.currentStage),
        .allRemaining: FakeTaskReviewRepository.plan(.allRemaining),
    ])
    /// Answered in order; once empty every approval goes through.
    public let outcomes = LockedValue<[ApprovalOutcome?]>([])
    public let sent = LockedValue<[ApprovalSend]>([])
    public let drafts = LockedValue<[FormDraft]?>([])
    public let closure = LockedValue<EmployeeClosure?>(
        EmployeeClosure(needsExpiration: false, nextExpiration: nil, canMerge: false, pdfs: [])
    )
    public let closureChoices = LockedValue<[ClosureChoice]>([])
    public let options = LockedValue<[SendBackOption]?>([
        SendBackOption(approvalId: 11, name: "Priya Raman", role: "Assignee")
    ])
    public let sendBackFails = LockedValue(false)
    public let sentBack = LockedValue<[SentBack]>([])
    public let late = LockedValue<LateContext?>(FakeTaskReviewRepository.satisfied())
    public let reasons = LockedValue<[ChangeReason]?>([
        ChangeReason(
            id: 1,
            name: "Participant unavailable",
            description: nil,
            requiresEvidence: true,
            preset: "Participant was unavailable."
        ),
        ChangeReason(id: 2, name: "Waiting on outside agency", description: nil, requiresEvidence: false),
    ])
    public let justifyFails = LockedValue(false)
    public let justified = LockedValue<[Justified]>([])
    public let agreed = LockedValue<[Agreed]>([])

    public init() {}

    public static func plan(_ mode: ApprovalMode, willComplete: Bool = false) -> ApprovalPlan {
        ApprovalPlan(
            mode: mode,
            willComplete: willComplete || mode == .allRemaining,
            requirementsVersion: "r1",
            workflowVersion: "w1",
            canApproveAll: true,
            remainingStages: 2
        )
    }

    public static func satisfied() -> LateContext {
        LateContext(canSubmit: true, canReview: false, reviewedByMe: false, satisfied: true)
    }

    public func plan(taskId: Int, mode: ApprovalMode) async throws -> ApprovalPlan {
        guard let plan = plans.get()[mode] else { throw failure.get() }
        return plan
    }

    public func approve(taskId: Int, send: ApprovalSend) async throws -> ApprovalOutcome {
        sent.update { $0.append(send) }
        let queued = outcomes.update { list -> [ApprovalOutcome?] in
            guard !list.isEmpty else { return [] }
            return [list.removeFirst()]
        }
        guard let next = queued.first else { return .approved(completed: send.plan.willComplete) }
        guard let outcome = next else { throw failure.get() }
        return outcome
    }

    public func drafts(taskId: Int) async throws -> [FormDraft] {
        guard let drafts = drafts.get() else { throw failure.get() }
        return drafts
    }

    public func employeeClosure(taskId: Int) async throws -> EmployeeClosure {
        guard let closure = closure.get() else { throw failure.get() }
        return closure
    }

    public func chooseClosure(taskId: Int, merge: [String]?, nextExpiration: CalendarDate?) async throws {
        closureChoices.update { $0.append(ClosureChoice(merge: merge, nextExpiration: nextExpiration)) }
    }

    public func sendBackOptions(taskId: Int) async throws -> [SendBackOption] {
        guard let options = options.get() else { throw failure.get() }
        return options
    }

    public func sendBack(
        taskId: Int,
        option: SendBackOption,
        feedback: String,
        minutes: Int,
        lateReasonId: Int64?
    ) async throws {
        sentBack.update {
            $0.append(
                SentBack(
                    approvalId: option.approvalId,
                    feedback: feedback,
                    minutes: minutes,
                    lateReasonId: lateReasonId
                )
            )
        }
        if sendBackFails.get() { throw failure.get() }
    }

    public func lateContext(taskId: Int) async throws -> LateContext {
        guard let late = late.get() else { throw failure.get() }
        return late
    }

    public func lateReasons() async throws -> [ChangeReason] {
        guard let reasons = reasons.get() else { throw failure.get() }
        return reasons
    }

    public func justify(
        taskId: Int,
        reasonId: Int64,
        explanation: String,
        evidenceId: Int?,
        delayId: Int64?
    ) async throws {
        justified.update {
            $0.append(Justified(reasonId: reasonId, explanation: explanation, evidenceId: evidenceId, delayId: delayId))
        }
        if justifyFails.get() { throw failure.get() }
        late.update { $0 = Self.satisfied() }
    }

    public func agreeLate(taskId: Int, justificationId: Int64, note: String?, edit: LateEdit?) async throws {
        agreed.update { $0.append(Agreed(justificationId: justificationId, note: note, edit: edit)) }
    }
}
