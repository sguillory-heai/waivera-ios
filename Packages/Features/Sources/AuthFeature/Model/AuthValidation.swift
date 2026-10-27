import Foundation

/// A problem with one field, shown under it. The view turns it into copy (`AuthStrings`), so
/// provider or server text can never reach a field.
public enum AuthFieldIssue: Equatable, Hashable, Sendable {
    case emailRequired
    case emailInvalid
    case passwordRequired
    case currentPasswordRequired
    /// Firebase rejected the current password during re-authentication.
    case currentPasswordWrong
    case newPasswordTooShort(minimum: Int)
    case newPasswordSameAsCurrent
    /// Firebase's password policy rejected the new password.
    case newPasswordWeak
    case confirmationMismatch
}

/// Client-side checks that run before anything is sent. They only catch obvious mistakes;
/// Firebase and the server stay the authority (a weak password is still rejected by
/// Firebase's policy).
public enum AuthValidation {
    /// New passwords need at least this many characters. Firebase's own floor is 6; 8 matches
    /// common organisation policy (open question in PLAN.md) and matches Android.
    public static let minimumNewPasswordLength = 8

    /// The email exactly as it is sent: trimmed, case kept (Firebase compares case-insensitively).
    public static func normalizedEmail(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// One `@`, something on both sides and a dot in the domain. Deliberately loose: the server
    /// decides what a real address is, this only catches typos such as a missing `@`.
    public static func emailIssue(_ raw: String) -> AuthFieldIssue? {
        let email = normalizedEmail(raw)
        if email.isEmpty { return .emailRequired }
        return looksLikeEmail(email) ? nil : .emailInvalid
    }

    /// The sign-in password is never trimmed: spaces can be part of it.
    public static func signInPasswordIssue(_ password: String) -> AuthFieldIssue? {
        password.isEmpty ? .passwordRequired : nil
    }

    public struct PasswordChangeIssues: Equatable, Sendable {
        public var current: AuthFieldIssue?
        public var new: AuthFieldIssue?
        public var confirmation: AuthFieldIssue?

        public init(current: AuthFieldIssue? = nil, new: AuthFieldIssue? = nil, confirmation: AuthFieldIssue? = nil) {
            self.current = current
            self.new = new
            self.confirmation = confirmation
        }

        public var isValid: Bool { current == nil && new == nil && confirmation == nil }
    }

    public static func passwordChangeIssues(current: String, new: String, confirmation: String) -> PasswordChangeIssues
    {
        var issues = PasswordChangeIssues()
        if current.isEmpty { issues.current = .currentPasswordRequired }
        if new.count < minimumNewPasswordLength {
            issues.new = .newPasswordTooShort(minimum: minimumNewPasswordLength)
        } else if !current.isEmpty && new == current {
            issues.new = .newPasswordSameAsCurrent
        }
        if confirmation != new { issues.confirmation = .confirmationMismatch }
        return issues
    }

    private static func looksLikeEmail(_ email: String) -> Bool {
        guard !email.contains(where: \.isWhitespace) else { return false }
        let parts = email.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        return domain.count >= 2 && domain.allSatisfy { !$0.isEmpty }
    }
}
