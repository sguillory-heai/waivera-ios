import Foundation
import WaiveraRouting

/// A modern chat push (`data.type == "chat"`, push.md §2).
public struct ChatPush: Equatable, Sendable {
    public let conversationID: Int
    public let messageID: Int?
    /// Not sent today; read when sprout_api adds it so thread replies open the thread (gap G-07/09-push §6).
    public let threadRootMessageID: Int?
    /// Expo-router path, kept only as a fallback (push.md §2d).
    public let url: String?

    public init(conversationID: Int, messageID: Int? = nil, threadRootMessageID: Int? = nil, url: String? = nil) {
        self.conversationID = conversationID
        self.messageID = messageID
        self.threadRootMessageID = threadRootMessageID
        self.url = url
    }

    /// A reply inside a thread (once sprout_api sends `threadRootMessageId`). It does not show
    /// in the main timeline, so the conversation being on screen never hides it.
    public var isThreadReply: Bool {
        guard let threadRootMessageID else { return false }
        return threadRootMessageID != messageID
    }
}

/// Every push shape the app may receive, decoded defensively (push.md "Defensive decoding rule").
public enum PushPayload: Equatable, Sendable {
    case chat(ChatPush)
    /// A chat push whose `conversationId` is missing, zero or not a number: the app opens
    /// normally and does not navigate (09-push §10).
    case invalidChat
    /// Legacy `NotificationType: "meeting"` (participant-targeted today, push.md §4).
    case meeting(eventID: String?)
    /// Legacy `NotificationType: "call"`.
    case call(conversationID: Int?, roomID: String?)
    /// Legacy `NotificationType: "Survey"`. No survey screen exists in the staff app.
    case survey(instanceID: String?)
    /// Anything else, including a future `type` this build does not know. Opens the inbox.
    case unknown(type: String?)

    /// The aps `category` and `thread-id`, when present, for grouping and meaning.
    public struct APSInfo: Equatable, Sendable {
        public let category: String?
        public let threadID: String?

        public init(category: String?, threadID: String?) {
            self.category = category
            self.threadID = threadID
        }
    }

    /// Where a tap on this push goes. `nil` means stay where the app opens.
    public var destination: Destination? {
        switch self {
        case .chat(let chat):
            if let rootID = chat.threadRootMessageID, rootID != chat.messageID {
                return .thread(
                    rootMessageID: rootID,
                    conversationID: chat.conversationID,
                    targetMessageID: chat.messageID
                )
            }
            return .conversation(chat.conversationID, targetMessageID: chat.messageID)
        case .invalidChat:
            return nil
        case .meeting(let eventID):
            return eventID.map(Destination.calendarEvent) ?? .schedule
        case .call(let conversationID, _):
            return conversationID.map { .conversation($0) } ?? .inbox
        case .survey:
            return .today
        case .unknown:
            return .inbox
        }
    }

    /// The conversation a push belongs to, for the presentation rule and Mark read.
    public var conversationID: Int? {
        switch self {
        case .chat(let chat): chat.conversationID
        case .call(let conversationID, _): conversationID
        default: nil
        }
    }

    public var isChat: Bool {
        if case .chat = self { return true }
        return false
    }
}

/// Parses notification `userInfo` (FCM puts `data` keys at the top level beside `aps`) and
/// FCM data maps. Values may arrive as strings (FCM) or numbers (Expo, simulator payloads).
public enum PushPayloadParser {
    public static func parse(userInfo: [AnyHashable: Any]) -> PushPayload {
        var flat: [String: String] = [:]
        for (key, value) in userInfo {
            guard let key = key as? String, let text = stringValue(value) else { continue }
            flat[key] = text
        }
        return parse(data: flat)
    }

    public static func parse(data: [String: String]) -> PushPayload {
        if let type = nonEmpty(data["type"]) {
            return parseModern(type: type, data: data)
        }
        if let legacyType = nonEmpty(data["NotificationType"]) {
            return parseLegacy(type: legacyType, data: data)
        }
        return .unknown(type: nil)
    }

    public static func apsInfo(userInfo: [AnyHashable: Any]) -> PushPayload.APSInfo {
        let aps = userInfo["aps"] as? [String: Any]
        return PushPayload.APSInfo(
            category: aps?["category"] as? String,
            threadID: aps?["thread-id"] as? String
        )
    }

    private static func parseModern(type: String, data: [String: String]) -> PushPayload {
        switch type.lowercased() {
        case "chat":
            guard let conversationID = nonEmpty(data["conversationId"]).flatMap(Identifier.positiveInt) else {
                return .invalidChat
            }
            return .chat(
                ChatPush(
                    conversationID: conversationID,
                    messageID: nonEmpty(data["messageId"]).flatMap(Identifier.positiveInt),
                    threadRootMessageID: nonEmpty(data["threadRootMessageId"]).flatMap(Identifier.positiveInt),
                    url: nonEmpty(data["url"])
                )
            )
        default:
            return .unknown(type: type)
        }
    }

    private static func parseLegacy(type: String, data: [String: String]) -> PushPayload {
        switch type.lowercased() {
        case "meeting":
            return .meeting(eventID: nonEmpty(data["CalenderEventId"]).flatMap(Identifier.opaque))
        case "call":
            return .call(
                conversationID: nonEmpty(data["conversationId"]).flatMap(Identifier.positiveInt),
                roomID: nonEmpty(data["roomId"]).flatMap(Identifier.opaque)
            )
        case "survey":
            return .survey(instanceID: nonEmpty(data["InstanceId"]).flatMap(Identifier.opaque))
        default:
            return .unknown(type: type)
        }
    }

    private static func stringValue(_ value: Any) -> String? {
        switch value {
        case let text as String: text
        case let number as Int: String(number)
        case let number as Int64: String(number)
        case let number as Double where number.rounded() == number && abs(number) < 1e15: String(Int(number))
        default: nil
        }
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespaces), !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
