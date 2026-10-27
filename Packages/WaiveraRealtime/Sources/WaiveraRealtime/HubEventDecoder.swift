import Foundation
import WaiveraAPI

/// One server-to-client invocation: the target and its positional arguments as raw JSON.
/// This is also the fixture format in `spec/fixtures/hub-*.json`.
public struct HubInvocation: Codable, Sendable, Equatable {
    public var target: String
    public var arguments: [JSONValue]

    public init(target: String, arguments: [JSONValue]) {
        self.target = target
        self.arguments = arguments
    }
}

/// Turns raw invocations into typed events. Keys are matched case-insensitively and enums
/// accept integers (the shared `WaiveraJSON` decoder does both, gap G-03). Malformed events
/// decode to `nil` and are dropped rather than crashing the connection.
public enum HubEventDecoder {
    public static func decode(_ invocation: HubInvocation) -> ChatHubEvent? {
        let args = invocation.arguments
        typealias Event = ChatHubContract.Event
        switch invocation.target.lowercased() {
        case Event.receiveMessage.lowercased():
            return object(args, MessageSendResponse.self).map(ChatHubEvent.message)
        case Event.receiveConversationListMessage.lowercased():
            return object(args, MessageSendResponse.self).map(ChatHubEvent.conversationListMessage)
        case Event.receiveChatAttention.lowercased():
            guard let message = object(args, MessageSendResponse.self) else { return nil }
            return .attention(message, reason: AttentionReason(lenient: args[safe: 1]?.stringValue))
        case Event.receiveChatActivity.lowercased():
            return object(args, ChatActivityResponse.self).map(ChatHubEvent.activity)
        case Event.removeChatActivity.lowercased():
            return removedActivityId(args.first).map { ChatHubEvent.activityRemoved(id: $0) }
        case Event.receiveChatReadState.lowercased():
            return object(args, ChatReadState.self).map(ChatHubEvent.readState)
        case Event.receiveTypingStatusForUser.lowercased():
            return typing(args)
        case Event.receiveReadReceipt.lowercased():
            return readReceipt(args)
        case Event.receiveReaction.lowercased():
            return reaction(args)
        default:
            return decodeSecondary(invocation.target.lowercased(), args)
        }
    }

    private static func decodeSecondary(_ target: String, _ args: [JSONValue]) -> ChatHubEvent? {
        typealias Event = ChatHubContract.Event
        switch target {
        case Event.receiveBookmarkUpdate.lowercased():
            return .bookmark(object(args, BookmarkUpdateEvent.self))
        case Event.receiveMessageUpdate.lowercased():
            return object(args, MessageUpdateEvent.self).map(ChatHubEvent.messageUpdated)
        case Event.receiveMessageDelete.lowercased():
            return object(args, MessageDeleteEvent.self).map(ChatHubEvent.messageDeleted)
        case Event.conversationCreated.lowercased():
            return object(args, ConversationResponse.self).map(ChatHubEvent.conversationCreated)
        case Event.conversationCallStateChanged.lowercased():
            return object(args, CallStateChangedEvent.self).map(ChatHubEvent.callStateChanged)
        case Event.removeAdHocFromConversation.lowercased():
            if let event = object(args, RemoveAdHocEvent.self) { return .adHocRemoved(event) }
            return args.first?.intValue.map { .adHocRemoved(RemoveAdHocEvent(conversationId: $0, roomId: nil)) }
        case Event.receiveNotification.lowercased(), Event.receiveNotificationWeb.lowercased():
            return object(args, EventNotificationResponse.self).map(ChatHubEvent.notification)
        case Event.receiveComment.lowercased():
            return args.first.map(ChatHubEvent.taskComment)
        default:
            return nil
        }
    }

    public static func decodeVideo(_ invocation: HubInvocation) -> VideoHubEvent? {
        typealias Event = VideoHubContract.Event
        let payload = invocation.arguments.first ?? .null
        switch invocation.target {
        case Event.receiveGroupCallInvite:
            return (try? payload.decode(as: GroupCallInvite.self)).map(VideoHubEvent.groupCallInvite)
        case Event.receiveExternalGroupCallInvite:
            return (try? payload.decode(as: GroupCallInvite.self)).map(VideoHubEvent.externalGroupCallInvite)
        case Event.callRejected:
            return .callRejected(roomId: payload["roomId"]?.stringValue, callerId: payload["callerId"]?.stringValue)
        case _ where VideoHubContract.Event.signatures[invocation.target] != nil:
            return .media(target: invocation.target, payload: payload)
        default:
            return nil
        }
    }

    private static func object<T: Decodable>(_ args: [JSONValue], _ type: T.Type) -> T? {
        guard let first = args.first, first.objectValue != nil else { return nil }
        return try? first.decode(as: type)
    }

    /// A bare number (`[4410]`) per the contract, tolerating `{ "id": 4410 }`.
    private static func removedActivityId(_ value: JSONValue?) -> Int64? {
        if let number = value?.intValue { return Int64(number) }
        if let nested = value?["id"]?.intValue ?? value?["Id"]?.intValue { return Int64(nested) }
        return nil
    }

    private static func typing(_ args: [JSONValue]) -> ChatHubEvent? {
        guard let conversationId = args[safe: 0]?.intValue, conversationId > 0,
            let userId = identifier(args[safe: 1]),
            let isTyping = args[safe: 2]?.boolValue
        else { return nil }
        return .typing(TypingEvent(conversationId: conversationId, userId: userId, isTyping: isTyping))
    }

    private static func readReceipt(_ args: [JSONValue]) -> ChatHubEvent? {
        guard let conversationId = args[safe: 0]?.intValue, let userId = identifier(args[safe: 1]) else { return nil }
        let lastReadAt = args[safe: 2]?.stringValue.flatMap(WaiveraInstant.parse)
        return .readReceipt(ReadReceiptEvent(conversationId: conversationId, userId: userId, lastReadAt: lastReadAt))
    }

    private static func reaction(_ args: [JSONValue]) -> ChatHubEvent? {
        guard let conversationId = args[safe: 0]?.intValue,
            let messageId = args[safe: 1]?.intValue,
            let userId = identifier(args[safe: 2])
        else { return nil }
        let type = args[safe: 3]?.stringValue
        var action = ReactionEvent.Action(lenient: args[safe: 4]?.stringValue)
        if action == .unknown { action = type == nil ? .removed : .updated }
        return .reaction(
            ReactionEvent(
                conversationId: conversationId,
                messageId: messageId,
                userId: userId,
                reactionType: type,
                action: action
            )
        )
    }

    private static func identifier(_ value: JSONValue?) -> String? {
        if let string = value?.stringValue, !string.isEmpty { return string }
        return value?.intValue.map(String.init)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
