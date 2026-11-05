import Foundation
import WaiveraAPI
import WaiveraData

/// Which button started the chain; it names the progress and the result.
enum ReviewAction: Sendable, Hashable {
    case submit, submitAll, approve, approveAll

    var mode: ApprovalMode { self == .submitAll || self == .approveAll ? .allRemaining : .currentStage }
    var submits: Bool { self == .submit || self == .submitAll }
}

/// The late reason: sent by the assignee before a late task moves on (web
/// `LateTaskJustificationModalV2`), or corrected by a reviewer as they agree with it
/// (`editingId`, web `LateJustificationReviewModal` edit mode).
struct LateForm: Sendable, Equatable {
    static let maxExplanation = 4_000

    var reasons: Loadable<[ChangeReason]> = .loading
    var reasonId: Int64?
    var explanation = ""
    /// Something was typed, so picking a reason no longer replaces the explanation with its preset.
    var typed = false
    /// A reported delay's reason and explanation are reused, with its evidence.
    var delayId: Int64?
    var delayEvidenceId: Int?
    /// Evidence already on the reason being corrected.
    var existingEvidenceId: Int?
    var evidence: PreparedFile?
    /// The picked file once uploaded, so a retry after a failed send reuses it; removable like the pick.
    var uploadedEvidenceId: Int?
    var evidenceChecking = false
    var evidenceProblem: UploadProblem?
    /// Returned for correction: the reviewer's feedback, shown above the fields.
    var returned = false
    var correction: String?
    /// A reviewer's correction of this reason, saved as they agree.
    var editingId: Int64?
    var due: CalendarDate?
    var isSaving = false
    var showErrors = false
    var failed = false

    var reason: ChangeReason? { reasons.value?.first { $0.id == reasonId } }
    var keptEvidenceId: Int? { uploadedEvidenceId ?? (delayId != nil ? delayEvidenceId : existingEvidenceId) }
    var evidenceMissing: Bool { reason?.requiresEvidence == true && evidence == nil && keptEvidenceId == nil }
    var reasonMissing: Bool { reasonId == nil }
    var explanationMissing: Bool { explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var explanationTooLong: Bool { explanation.count > Self.maxExplanation }
    var isValid: Bool {
        !reasonMissing && !explanationMissing && !explanationTooLong && !evidenceMissing && !evidenceChecking
    }
}

/// The reviewer's look at a submitted late reason: agree, correct it, or send the task back.
struct LateCheck: Sendable, Equatable {
    static let maxNote = 2_000

    var context: LateContext
    var note = ""
    var isSaving = false
    var failed = false

    var noteTooLong: Bool { note.count > Self.maxNote }
}

/// Send back for changes (web `RejectTaskModal`), or return a late reason for correction (`lateReasonId`).
struct SendBackForm: Sendable, Equatable {
    static let maxMinutes = 24 * 60
    static let maxFeedback = 2_000
    static let minuteDigits = 4

    var options: Loadable<[SendBackOption]> = .loading
    var approvalId: Int?
    var feedback = ""
    var minutes = ""
    var lateReasonId: Int64?
    var isSaving = false
    var showErrors = false
    var failed = false

    var option: SendBackOption? { options.value?.first { $0.approvalId == approvalId } }
    var noOptions: Bool { options.value?.isEmpty == true }
    var returnsLateReason: Bool { lateReasonId != nil }
    var minutesValue: Int? {
        if minutes.isEmpty { return 0 }
        guard let value = Int(minutes), (0...Self.maxMinutes).contains(value) else { return nil }
        return value
    }
    var optionMissing: Bool { option == nil }
    var feedbackMissing: Bool { feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var feedbackTooLong: Bool { feedback.count > Self.maxFeedback }
    var minutesInvalid: Bool { minutesValue == nil }
    var isValid: Bool { !optionMissing && !feedbackMissing && !feedbackTooLong && !minutesInvalid }
}

/// How an employee task's files are finalized as it completes (web employee closure prompt).
struct ClosureForm: Sendable, Equatable {
    static let minMerge = 2

    var options: EmployeeClosure
    var merge = false
    /// The PDFs to merge, in order; every eligible PDF starts picked, as on the web.
    var order: [String]
    var picked: Set<String>
    var expiration: CalendarDate?
    var isSaving = false
    var showErrors = false
    var failed = false

    init(options: EmployeeClosure) {
        self.options = options
        order = options.pdfs.map(\.id)
        picked = Set(options.pdfs.map(\.id))
        expiration = options.nextExpiration
    }

    var tooFewPicked: Bool { merge && picked.count < Self.minMerge }
    var expirationMissing: Bool { options.needsExpiration && expiration == nil }
    var isValid: Bool { !tooFewPicked && !expirationMissing }
}

/// A field problem, worded by the sheet. `date` is the expected date some warnings name.
struct RequirementIssue: Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        case required, invalidDate, endBeforeStart, overAYearAgo, expectedStart, expectedEnd
    }

    var kind: Kind
    var date: CalendarDate?
}

/// The stage's own requirements (web `WorkflowApprovalRequirementsModal`). `values` are keyed by
/// action id, then field key; dates are ISO `YYYY-MM-DD`. Warnings need a second tap to approve.
struct RequirementsForm: Sendable, Equatable {
    var requirements: [StageRequirement]
    var values: [Int: [String: String]]
    var errors: [Int: [String: RequirementIssue]] = [:]
    var warnings: [Int: [String: RequirementIssue]] = [:]
    var confirmWarnings = false
    /// The server changed what this stage needs while the sheet was open.
    var changed = false
    var isSaving = false
    var failed = false

    var supported: Bool { requirements.allSatisfy(\.supported) }
    var hasWarnings: Bool { warnings.values.contains { !$0.isEmpty } }
}

/// One sheet of the chain at a time.
enum ReviewStep: Sendable, Equatable {
    case lateReason(LateForm)
    case lateReview(LateCheck)
    case confirmAll(stages: Int, submit: Bool)
    case drafts([String])
    case driveSection(previous: CalendarDate, useOriginal: Bool)
    case closure(ClosureForm)
    case requirements(RequirementsForm)
    /// A related task holds this one up; `blocked` means it can't complete at all yet.
    case related(blocked: Bool, tasks: [RelatedTask], isSaving: Bool)
    case sendBack(SendBackForm)

    /// The sheet is sending its answer, as opposed to waiting for the person.
    var isSaving: Bool {
        switch self {
        case .lateReason(let form): form.isSaving
        case .lateReview(let check): check.isSaving
        case .closure(let form): form.isSaving
        case .requirements(let form): form.isSaving
        case .related(_, _, let saving): saving
        case .sendBack(let form): form.isSaving
        case .confirmAll, .drafts, .driveSection: false
        }
    }

    func withSaving(_ saving: Bool) -> ReviewStep {
        switch self {
        case .lateReason(var form):
            form.isSaving = saving
            return .lateReason(form)
        case .lateReview(var check):
            check.isSaving = saving
            return .lateReview(check)
        case .closure(var form):
            form.isSaving = saving
            return .closure(form)
        case .requirements(var form):
            form.isSaving = saving
            return .requirements(form)
        case .related(let blocked, let tasks, _): return .related(blocked: blocked, tasks: tasks, isSaving: saving)
        case .sendBack(var form):
            form.isSaving = saving
            return .sendBack(form)
        case .confirmAll, .drafts, .driveSection: return self
        }
    }
}

struct ReviewState: Sendable, Equatable {
    var step: ReviewStep?
    /// Which button is working through the chain, for its progress label.
    var running: ReviewAction?
    var rejecting = false

    var stepSaving: Bool { step?.isSaving ?? false }
    var busy: Bool { running != nil || rejecting }
}

/// What the screen does once a chain ends.
enum ReviewEffect: Sendable, Hashable {
    /// The task moved on; `completed` when this approval finished it.
    case done(ReviewAction, completed: Bool)
    case sentBack
    /// Someone else acted first, or the workflow changed: the task was refreshed.
    case changed
    /// A step failed before any sheet was open.
    case failed
    /// A late reason is needed and only the assignee or their manager can send it.
    case lateNeedsAssignee
    case cantApproveAll
    /// The task needs reloading (always sent after the chain changes it).
    case reload
    case openTask(taskId: Int)

    var message: String? {
        switch self {
        case .done(let action, let completed):
            if completed { return TasksStrings.text("tasks.review.doneCompleted") }
            return TasksStrings.text(action.submits ? "tasks.review.submitted" : "tasks.review.approved")
        case .sentBack: return TasksStrings.text("tasks.review.sentBack")
        case .changed: return TasksStrings.text("tasks.review.taskChanged")
        case .failed: return TasksStrings.text("tasks.review.failed")
        case .lateNeedsAssignee: return TasksStrings.text("tasks.review.lateNeedsAssignee")
        case .cantApproveAll: return TasksStrings.text("tasks.review.cantAll")
        case .reload, .openTask: return nil
        }
    }
}

/// "Step 2 of 4 · Supervisor", and who approved the stage before it.
struct StepNote: Sendable, Hashable {
    var order: Int
    var total: Int
    var role: String?
    var sentBy: String?

    static func of(_ steps: [WorkflowStep]) -> StepNote? {
        guard let active = steps.firstIndex(where: { $0.status == .active }) else { return nil }
        let before = steps[..<active].last { $0.status == .completed }
        return StepNote(order: active + 1, total: steps.count, role: steps[active].role, sentBy: before?.approverName)
    }

    var text: String {
        if let role { return TasksStrings.format("tasks.review.step", String(order), String(total), role) }
        return TasksStrings.format("tasks.review.stepPlain", String(order), String(total))
    }
}
