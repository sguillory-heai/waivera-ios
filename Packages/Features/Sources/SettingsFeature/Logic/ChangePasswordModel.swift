import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// A field-level problem with the change-password form. The view turns each into copy.
public enum PasswordFieldError: Equatable, Sendable {
    case currentRequired
    case currentWrong
    case tooShort(minimum: Int)
    case sameAsCurrent
    case mismatch
}

/// The voluntary change-password sheet from Settings → Account (the forced change after
/// sign-in is the auth feature's gate). Validates locally first, then calls
/// `SessionRepository.changePassword`, which updates Firebase and confirms with sprout_api.
@MainActor
@Observable
public final class ChangePasswordModel {
    /// Matches the auth feature's rule (PLAN.md open question: org policy may raise it).
    public static let minimumLength = 8

    public var current = "" {
        didSet { if current != oldValue { currentError = nil; failure = nil } }
    }

    public var new = "" {
        didSet { if new != oldValue { newError = nil; failure = nil } }
    }

    public var confirmation = "" {
        didSet { if confirmation != oldValue { confirmationError = nil } }
    }

    public private(set) var currentError: PasswordFieldError?
    public private(set) var newError: PasswordFieldError?
    public private(set) var confirmationError: PasswordFieldError?
    /// A failure that is not about one field (offline, server, too many attempts).
    public private(set) var failure: WaiveraError?
    public private(set) var isSubmitting = false
    public private(set) var didSucceed = false
    /// Counts rejected submits (validation or server).
    public private(set) var submitFailures = 0

    @ObservationIgnored private let session: any SessionRepository

    public init(session: any SessionRepository) {
        self.session = session
    }

    public var canSubmit: Bool {
        !isSubmitting && !current.isEmpty && !new.isEmpty && !confirmation.isEmpty
    }

    /// Validates every field at once so all problems show together. Returns whether it passed.
    @discardableResult
    public func validate() -> Bool {
        currentError = current.isEmpty ? .currentRequired : nil
        newError =
            if new.count < Self.minimumLength {
                .tooShort(minimum: Self.minimumLength)
            } else if new == current {
                .sameAsCurrent
            } else {
                nil
            }
        confirmationError = confirmation == new ? nil : .mismatch
        return currentError == nil && newError == nil && confirmationError == nil
    }

    /// Returns `true` when the password changed. Double submits are ignored.
    public func submit() async -> Bool {
        guard !isSubmitting, !didSucceed else { return false }
        guard validate() else {
            submitFailures += 1
            return false
        }
        isSubmitting = true
        failure = nil
        defer { isSubmitting = false }
        do {
            try await session.changePassword(current: current, new: new)
            didSucceed = true
            current = ""
            new = ""
            confirmation = ""
            return true
        } catch {
            let mapped = WaiveraError.from(error)
            switch mapped {
            case .auth(.invalidCredentials): currentError = .currentWrong
            case .auth(.weakPassword): newError = .tooShort(minimum: Self.minimumLength)
            default: failure = mapped
            }
            submitFailures += 1
            return false
        }
    }
}
