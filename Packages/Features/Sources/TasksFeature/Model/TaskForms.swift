import Foundation
import WaiveraAPI
import WaiveraData

/// The Log activity sheet. A type with a fixed description or a recommended time locks that
/// field, as on the web. Times are picked in the employee's saved zone and sent as a UTC instant.
struct LogForm: Equatable, Sendable {
    static let defaultMinutes = 15
    static let stepMinutes = 15
    static let maxMinutes = 24 * 60
    static let maxDescription = 4_000

    var types: Loadable<[ActivityType]> = .loading
    var typeId: Int?
    var minutes = LogForm.defaultMinutes
    var completedAt: Date
    var description = ""
    var isSaving = false
    var showErrors = false
    var failed = false
    /// The picked time is after now; filled in by the model.
    var inFuture = false
    /// "Today, 2:30 PM" in the saved zone; filled in by the model.
    var whenText = ""

    var type: ActivityType? { types.value?.first { $0.id == typeId } }
    var minutesLocked: Bool { type?.recommendedMinutes != nil }
    var descriptionLocked: Bool { type?.fixedDescription != nil }
    var typeMissing: Bool { typeId == nil }
    var descriptionMissing: Bool { description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isValid: Bool { !typeMissing && !descriptionMissing && !inFuture && minutes > 0 }
}

/// The three changes a person can ask for on a task, in the order the chooser offers them.
enum AskKind: Hashable, Sendable, CaseIterable {
    case moreTime
    case delay
    case closure

    var title: String {
        switch self {
        case .moreTime: TasksStrings.text("tasks.ask.moreTime")
        case .delay: TasksStrings.text("tasks.ask.delay")
        case .closure: TasksStrings.text("tasks.ask.closure")
        }
    }

    var detail: String {
        switch self {
        case .moreTime: TasksStrings.text("tasks.ask.moreTime.detail")
        case .delay: TasksStrings.text("tasks.ask.delay.detail")
        case .closure: TasksStrings.text("tasks.ask.closure.detail")
        }
    }

    var requestKind: RequestKind {
        switch self {
        case .moreTime: .moreTime
        case .delay: .delay
        case .closure: .closure
        }
    }
}

/// The Ask for a change sheet. `kind` nil is the chooser. The rules match the web's forms: a new
/// due date after the current one and within five years, an explanation of at most 4,000
/// characters, and a file already on the task when the reason needs evidence.
struct AskForm: Equatable, Sendable {
    static let maxExplanation = 4_000
    static let maxYears = 5
    /// A little past the limit stays typed, so the count can say how much to remove.
    static let explanationSlack = 200

    var choices: [AskKind]
    var kind: AskKind?
    var reasons: Loadable<[ChangeReason]> = .loading
    var reasonId: Int64?
    var newDue: CalendarDate?
    var explanation = ""
    var files: Loadable<[TaskFileRef]> = .loading
    var evidenceId: Int?
    /// The due date the request moves, from the server's eligibility check.
    var currentDue: CalendarDate?
    /// The server-owned delay period; it can't be edited.
    var delay: DelayPeriod?
    var isSaving = false
    var showErrors = false
    var failed = false
    /// The delay period changed or closed since the sheet opened.
    var delayChanged = false

    var reason: ChangeReason? { reasons.value?.first { $0.id == reasonId } }
    var evidence: TaskFileRef? { files.value?.first { $0.attachmentId == evidenceId } }
    var needsEvidence: Bool { kind != .closure && reason?.requiresEvidence == true }

    var dueMissing: Bool { kind == .moreTime && newDue == nil }
    var dueTooEarly: Bool {
        guard kind == .moreTime, let newDue, let currentDue else { return false }
        return newDue <= currentDue
    }
    var dueTooLate: Bool {
        guard kind == .moreTime, let newDue, let currentDue else { return false }
        return newDue > currentDue.addingMonths(Self.maxYears * 12)
    }
    var reasonMissing: Bool { reasonId == nil }
    var explanationMissing: Bool {
        explanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (kind != .closure || reason?.needsComment == true)
    }
    var explanationTooLong: Bool { explanation.count > Self.maxExplanation }
    var evidenceMissing: Bool { needsEvidence && evidence == nil }
    var delayMissing: Bool { kind == .delay && delay == nil }

    var isValid: Bool {
        kind != nil && !dueMissing && !dueTooEarly && !dueTooLate && !reasonMissing && !explanationMissing
            && !explanationTooLong && !evidenceMissing && !delayMissing
    }
}
