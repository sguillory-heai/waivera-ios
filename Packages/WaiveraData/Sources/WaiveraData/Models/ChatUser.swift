import Foundation

/// A person as chat sees them. `id` is the backend user id (bots use `bot:`-prefixed ids).
public struct ChatUser: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var firstName: String?
    public var lastName: String?
    public var displayName: String?
    public var email: String?
    public var avatarURL: String?

    public init(
        id: String,
        firstName: String? = nil,
        lastName: String? = nil,
        displayName: String? = nil,
        email: String? = nil,
        avatarURL: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.displayName = displayName
        self.email = email
        self.avatarURL = avatarURL
    }

    public var isBot: Bool { id.hasPrefix("bot:") }

    /// "First Last", else display name, else email; `nil` when nothing usable is known, so
    /// the screen can use its own "Unknown" copy.
    public var fullName: String? {
        let parts = [firstName, lastName].compactMap { $0?.trimmed }.filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " ") }
        if let name = displayName?.trimmed, !name.isEmpty { return name }
        if let email = email?.trimmed, !email.isEmpty { return email }
        return nil
    }

    /// Short label for "A & 2 others" titles (02 §4): email local part, or "F. Last", or a
    /// truncated name.
    public var compactName: String? {
        guard let name = fullName else { return nil }
        if let at = name.firstIndex(of: "@") {
            let local = String(name[..<at])
            return local.count > 16 ? String(local.prefix(15)) + "…" : local
        }
        if name.count <= 18 { return name }
        let words = name.split(separator: " ")
        if words.count >= 2, let first = words.first?.first, let last = words.last {
            let short = "\(first). \(last)"
            if short.count <= 18 { return short }
        }
        return String(name.prefix(17)) + "…"
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whitespace runs collapsed to single spaces, trimmed.
    var collapsedWhitespace: String {
        split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}
