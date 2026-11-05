import Foundation
import WaiveraRouting

/// Who wrote a chat push, for the notification extension's sender photo (WAIV-2939). sprout_api
/// sends `senderId` on person messages only; bot messages have no person and keep the app icon.
public struct ChatSender: Equatable, Sendable {
    /// The sprout_api user id, as `GET api/file/avatar/{userId}` takes it.
    public let userID: String
    /// The alert title, which is the sender's display name.
    public let name: String
    /// Groups the conversation's notifications, as the alert's `thread-id` does.
    public let conversationID: Int

    public init(userID: String, name: String, conversationID: Int) {
        self.userID = userID
        self.name = name
        self.conversationID = conversationID
    }

    /// `nil` unless this is a chat push from a person with a usable id and name.
    public static func from(userInfo: [AnyHashable: Any], title: String) -> ChatSender? {
        guard case .chat(let chat) = PushPayloadParser.parse(userInfo: userInfo),
            let raw = (userInfo["senderId"] as? String)?.trimmingCharacters(in: .whitespaces),
            let userID = Identifier.opaque(raw)
        else { return nil }
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return nil }
        return ChatSender(userID: userID, name: name, conversationID: chat.conversationID)
    }
}
