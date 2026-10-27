import Foundation

/// Parses `waivera://` URLs (and the path-only form `/chats/7` that push payloads carry in
/// `data.url`) into a `Destination`. URLs are untrusted input: ids are validated and anything
/// unrecognised returns `nil` so the caller can fall back to the inbox.
///
/// Grammar (also in docs/architecture/app-shell.md):
/// ```
/// waivera://today | activity
/// waivera://chats | chats/new | chats/{conversationId}[?messageId=]
/// waivera://chats/thread/{rootId}[?conversationId=&messageId=]
/// waivera://chats/{conversationId}/thread/{rootId}[?messageId=]
/// waivera://schedule | calendar | calendar/{eventId} | calendar?eventId=
/// waivera://profile | profile/organization | people | people/{userId} | bookmarks
/// waivera://settings | settings/notifications | settings/appearance | settings/account
/// ```
public enum DeepLink {
    public static let scheme = "waivera"

    public static func destination(from url: URL) -> Destination? {
        guard url.scheme?.lowercased() == scheme else { return nil }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        var segments: [String] = []
        if let host = components.host, !host.isEmpty {
            segments.append(host)
        }
        segments += components.path.split(separator: "/").map(String.init)
        return destination(segments: segments, query: queryItems(components))
    }

    /// The path-only form, e.g. push `data.url` `/chats/7`. Only used as a fallback.
    public static func destination(fromPath path: String) -> Destination? {
        guard let components = URLComponents(string: path), components.scheme == nil, components.host == nil else {
            return nil
        }
        let segments = components.path.split(separator: "/").map(String.init)
        return destination(segments: segments, query: queryItems(components))
    }

    private static func queryItems(_ components: URLComponents) -> [String: String] {
        var result: [String: String] = [:]
        for item in components.queryItems ?? [] {
            if let value = item.value, result[item.name] == nil {
                result[item.name] = value
            }
        }
        return result
    }

    // One case per URL shape keeps the grammar readable next to the doc comment.
    // `URLComponents.path` is already percent-decoded; segments are never decoded twice.
    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func destination(segments: [String], query: [String: String]) -> Destination? {
        let messageID = query["messageId"].flatMap(Identifier.positiveInt)
        switch segments.first?.lowercased() {
        case nil, "today":
            return segments.count <= 1 ? .today : nil
        case "activity":
            return segments.count == 1 ? Destination(tab: .today, path: [.activity]) : nil
        case "chats", "chat":
            return chatDestination(Array(segments.dropFirst()), query: query, messageID: messageID)
        case "schedule":
            return segments.count == 1 ? .schedule : nil
        case "calendar":
            if segments.count == 1 {
                if let eventID = query["eventId"] {
                    return Identifier.opaque(eventID).map(Destination.calendarEvent)
                }
                return .schedule
            }
            guard segments.count == 2, let eventID = Identifier.opaque(segments[1]) else { return nil }
            return .calendarEvent(eventID)
        case "profile":
            if segments.count == 1 { return Destination(tab: nil, path: [.profile]) }
            guard segments.count == 2, segments[1].lowercased() == "organization" else { return nil }
            return Destination(tab: nil, path: [.profile, .organization])
        case "people":
            if segments.count == 1 { return Destination(tab: nil, path: [.people]) }
            guard segments.count == 2, let userID = Identifier.opaque(segments[1]) else { return nil }
            return Destination(tab: nil, path: [.people, .person(userID: userID)])
        case "bookmarks":
            return segments.count == 1 ? Destination(tab: nil, path: [.bookmarks]) : nil
        case "settings":
            if segments.count == 1 { return Destination(tab: nil, path: [.settings]) }
            guard segments.count == 2 else { return nil }
            let leaf: AppRoute
            switch segments[1].lowercased() {
            case "notifications": leaf = .notificationSettings
            case "appearance": leaf = .appearanceSettings
            case "account": leaf = .accountSettings
            default: return nil
            }
            return Destination(tab: nil, path: [.settings, leaf])
        default:
            return nil
        }
    }

    private static func chatDestination(_ rest: [String], query: [String: String], messageID: Int?) -> Destination? {
        switch rest.count {
        case 0:
            return .inbox
        case 1 where rest[0].lowercased() == "new":
            return Destination(tab: .chat, sheet: .newChat)
        case 1:
            guard let conversationID = Identifier.positiveInt(rest[0]) else { return nil }
            return .conversation(conversationID, targetMessageID: messageID)
        case 2 where rest[0].lowercased() == "thread":
            guard let rootID = Identifier.positiveInt(rest[1]) else { return nil }
            let conversationID = query["conversationId"].flatMap(Identifier.positiveInt)
            return .thread(rootMessageID: rootID, conversationID: conversationID, targetMessageID: messageID)
        case 3 where rest[1].lowercased() == "thread":
            guard let conversationID = Identifier.positiveInt(rest[0]), let rootID = Identifier.positiveInt(rest[2])
            else {
                return nil
            }
            return .thread(rootMessageID: rootID, conversationID: conversationID, targetMessageID: messageID)
        default:
            return nil
        }
    }
}

/// Validation for ids arriving from URLs and push payloads.
public enum Identifier {
    /// Longest opaque id accepted (user ids, event ids).
    public static let maxOpaqueLength = 128

    /// A decimal id greater than zero. Rejects signs, spaces, fractions and overflow.
    public static func positiveInt(_ text: String) -> Int? {
        guard !text.isEmpty, text.count <= 18, text.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        guard let value = Int(text), value > 0 else { return nil }
        return value
    }

    /// An opaque server id such as `usr_priya_raman` or `evt_8f2b19c4`: ASCII letters, digits
    /// and `_ - . :` only, so it is safe to put back into a request path.
    public static func opaque(_ text: String) -> String? {
        guard !text.isEmpty, text.count <= maxOpaqueLength else { return nil }
        // Dot-only segments would walk up a request path.
        guard !text.contains(".."), text != "." else { return nil }
        let allowed = text.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "_-.:".unicodeScalars.contains(scalar))
        }
        return allowed ? text : nil
    }
}
