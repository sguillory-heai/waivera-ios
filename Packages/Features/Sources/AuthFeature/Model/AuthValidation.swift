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
    /// The new password misses at least one `PasswordRule`; the checklist shows which.
    case newPasswordMissingRules
    case newPasswordSameAsCurrent
    /// The server's password policy rejected the new password.
    case newPasswordWeak
    case confirmationMismatch
}

/// One rule of sprout_api's `PasswordPolicy`, shown as a line of the new-password checklist.
public enum PasswordRule: CaseIterable, Hashable, Sendable {
    case length
    case uppercase
    case lowercase
    case number
    case symbol
}

/// Client-side checks that run before anything is sent. The new-password rules mirror
/// sprout_api's `Utilities/PasswordPolicy.cs` (and the web's `passwordPolicy.ts`) exactly, so a
/// password the form accepts is never refused by `change-password`; the server stays the authority.
public enum AuthValidation {
    /// `PasswordPolicy.MinimumLength`, counted in UTF-16 units like the server and the web.
    public static let minimumNewPasswordLength = 12

    /// `PasswordPolicy.SpecialCharacters`; nothing else counts as a symbol (not `-`, `+` or a space).
    public static let passwordSymbols = "^$*.[]{}()?\"!@#%&/\\,><':;|_~"

    private static let symbolScalars = Set(passwordSymbols.unicodeScalars)

    /// The rules `password` does not meet yet. Letters and digits are ASCII only, like the server's.
    public static func unmetPasswordRules(_ password: String) -> Set<PasswordRule> {
        let scalars = password.unicodeScalars
        var unmet = Set<PasswordRule>()
        if password.utf16.count < minimumNewPasswordLength { unmet.insert(.length) }
        if !scalars.contains(where: { (65...90).contains($0.value) }) { unmet.insert(.uppercase) }
        if !scalars.contains(where: { (97...122).contains($0.value) }) { unmet.insert(.lowercase) }
        if !scalars.contains(where: { (48...57).contains($0.value) }) { unmet.insert(.number) }
        if !scalars.contains(where: { symbolScalars.contains($0) }) { unmet.insert(.symbol) }
        return unmet
    }

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

    public static func passwordChangeIssues(
        current: String,
        new: String,
        confirmation: String
    ) -> PasswordChangeIssues {
        var issues = PasswordChangeIssues()
        if current.isEmpty { issues.current = .currentPasswordRequired }
        if !unmetPasswordRules(new).isEmpty {
            issues.new = .newPasswordMissingRules
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
