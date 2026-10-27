import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Changes the password: Firebase re-authenticates with the current password and sets the new
/// one, then the backend's `confirm-password-change` clears the gate and the session refreshes
/// (all inside `SessionRepository.changePassword`).
///
/// Two flows share it:
/// - **required**: the gate after sign-in. The only ways out are a new password or Sign out; on
///   success the session moves the gate on by itself.
/// - **voluntary**: from Settings. The screen calls its `onDone` once `phase == .done`.
@MainActor
@Observable
public final class PasswordChangeModel {
    public enum Mode: Sendable {
        case required
        case voluntary
    }

    public enum Phase: Equatable, Sendable {
        case editing
        case saving
        case done
    }

    public enum Field: Hashable, Sendable {
        case current
        case new
        case confirmation
    }

    public let mode: Mode
    public private(set) var current = ""
    public private(set) var new = ""
    public private(set) var confirmation = ""
    public private(set) var issues = AuthValidation.PasswordChangeIssues()
    /// A failure that belongs to no single field (offline, server). Client-owned copy only.
    public private(set) var error: WaiveraError?
    public private(set) var phase: Phase = .editing
    /// The field that should take focus after a failed submit, so the person lands on the problem.
    public private(set) var focusRequest: Field?
    public private(set) var failureCount = 0
    public private(set) var successCount = 0

    @ObservationIgnored private let session: (any SessionRepository)?

    public init(mode: Mode, session: (any SessionRepository)?) {
        self.mode = mode
        self.session = session
    }

    public var fieldsEnabled: Bool { phase == .editing && session != nil }
    public var canSubmit: Bool { fieldsEnabled && !current.isEmpty && !new.isEmpty && !confirmation.isEmpty }
    public var isSaving: Bool { phase == .saving }
    /// Shown under "New password" until it has its own error.
    public var showsNewPasswordHint: Bool { issues.new == nil }

    // MARK: Session

    /// Follows the session until the calling task is cancelled. A sign-out (from this screen or
    /// anywhere) wipes what was typed, so the next person never sees it.
    public func observeSession() async {
        guard let session else { return }
        for await state in session.states() {
            apply(state)
        }
    }

    func apply(_ state: SessionState) {
        if case .signedOut = state { reset() }
    }

    // MARK: Editing

    public func set(_ field: Field, to value: String) {
        switch field {
        case .current:
            guard value != current else { return }
            current = value
            issues.current = nil
        case .new:
            guard value != new else { return }
            new = value
            issues.new = nil
        case .confirmation:
            guard value != confirmation else { return }
            confirmation = value
            issues.confirmation = nil
        }
        error = nil
        if phase == .done { phase = .editing }
    }

    public func dismissError() {
        error = nil
    }

    public func focusHandled() {
        focusRequest = nil
    }

    // MARK: Submit

    public func submit() async {
        guard fieldsEnabled, let session else { return }
        let found = AuthValidation.passwordChangeIssues(current: current, new: new, confirmation: confirmation)
        guard found.isValid else {
            issues = found
            fail(focus: firstField(with: found))
            return
        }
        phase = .saving
        error = nil
        let (current, new) = (current, new)
        do {
            try await session.changePassword(current: current, new: new)
            // Drop every secret from memory as soon as it has been used.
            clearFields()
            phase = .done
            successCount += 1
        } catch {
            phase = .editing
            handle(WaiveraError.from(error))
        }
    }

    private func handle(_ failure: WaiveraError) {
        switch failure {
        case .auth(.invalidCredentials):
            // Wrong current password: point at that field and let them retype it.
            current = ""
            issues.current = .currentPasswordWrong
            fail(focus: .current)
        case .auth(.weakPassword):
            issues.new = .newPasswordWeak
            fail(focus: .new)
        default:
            error = failure
            fail(focus: nil)
        }
    }

    private func fail(focus: Field?) {
        focusRequest = focus
        failureCount += 1
    }

    private func firstField(with issues: AuthValidation.PasswordChangeIssues) -> Field? {
        if issues.current != nil { return .current }
        if issues.new != nil { return .new }
        if issues.confirmation != nil { return .confirmation }
        return nil
    }

    private func clearFields() {
        current = ""
        new = ""
        confirmation = ""
        issues = AuthValidation.PasswordChangeIssues()
    }

    private func reset() {
        clearFields()
        error = nil
        phase = .editing
        focusRequest = nil
    }
}

extension PasswordChangeModel: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Never prints a password, even in a debug log, a crash report or `dump`.
    public nonisolated var description: String { "PasswordChangeModel(redacted)" }
    public nonisolated var debugDescription: String { description }
    public nonisolated var customMirror: Mirror { Mirror(self, children: [], displayStyle: .class) }
}
