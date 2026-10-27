import Foundation
import WaiveraAPI

/// Every chat hub event as a typed value (hub.md §3).
public enum ChatHubEvent: Sendable, Equatable {
    /// To `conversation_{id}`; the sender gets its own echo.
    case message(MessageSendResponse)
    /// To every other participant, top-level messages only: "bump this inbox row".
    case conversationListMessage(MessageSendResponse)
    /// The authoritative "alert the user" signal (gap G-09).
    case attention(MessageSendResponse, reason: AttentionReason)
    case activity(ChatActivityResponse)
    case activityRemoved(id: Int64)
    case readState(ChatReadState)
    case typing(TypingEvent)
    case readReceipt(ReadReceiptEvent)
    case reaction(ReactionEvent)
    /// `nil` when the payload shape is not recognised; refetch bookmarks then.
    case bookmark(BookmarkUpdateEvent?)
    case messageUpdated(MessageUpdateEvent)
    case messageDeleted(MessageDeleteEvent)
    case conversationCreated(ConversationResponse)
    case callStateChanged(CallStateChangedEvent)
    case adHocRemoved(RemoveAdHocEvent)
    /// `ReceiveNotification` and `receivenotification_web` (in-app notification feed).
    case notification(EventNotificationResponse)
    /// Task comments (phase 2), kept raw.
    case taskComment(JSONValue)
}

public enum AttentionReason: String, OpenEnum {
    case mention
    case threadReply = "thread_reply"
    case message
    case unknown = "UNKNOWN"
    public static var unknownCase: AttentionReason { .unknown }
}

/// `ReceiveTypingStatusForUser(conversationId, userId, isTyping)`. No server expiry.
public struct TypingEvent: Sendable, Equatable {
    public var conversationId: Int
    public var userId: String
    public var isTyping: Bool

    public init(conversationId: Int, userId: String, isTyping: Bool) {
        self.conversationId = conversationId
        self.userId = userId
        self.isTyping = isTyping
    }
}

/// `ReceiveReadReceipt(conversationId, userId, lastReadAt?)`.
public struct ReadReceiptEvent: Sendable, Equatable {
    public var conversationId: Int
    public var userId: String
    public var lastReadAt: Date?

    public init(conversationId: Int, userId: String, lastReadAt: Date?) {
        self.conversationId = conversationId
        self.userId = userId
        self.lastReadAt = lastReadAt
    }
}

/// `ReceiveReaction(conversationId, messageId, userId, reactionType?, action)`. A user holds at
/// most one reaction per message; `reactionType` is nil exactly when removed.
public struct ReactionEvent: Sendable, Equatable {
    public enum Action: String, OpenEnum {
        case added
        case updated
        case removed
        case unknown = "UNKNOWN"
        public static var unknownCase: Action { .unknown }
    }

    public var conversationId: Int
    public var messageId: Int
    public var userId: String
    public var reactionType: String?
    public var action: Action

    public init(conversationId: Int, messageId: Int, userId: String, reactionType: String?, action: Action) {
        self.conversationId = conversationId
        self.messageId = messageId
        self.userId = userId
        self.reactionType = reactionType
        self.action = action
    }
}

/// `ReceiveBookmarkUpdate({ messageId, isBookmarked })`, own devices only.
public struct BookmarkUpdateEvent: Codable, Sendable, Equatable {
    public var messageId: Int
    public var isBookmarked: Bool

    public init(messageId: Int, isBookmarked: Bool) {
        self.messageId = messageId
        self.isBookmarked = isBookmarked
    }
}

/// `ReceiveMessageUpdate`. Note `newContent`, not `messageContent`.
public struct MessageUpdateEvent: Codable, Sendable, Equatable {
    public var messageId: Int
    public var conversationId: Int
    public var newContent: String?
    public var isEdited: Bool?
    public var updateDate: Date?
    public var contentFormat: Int?
    public var messageDoc: JSONValue?
    public var messagePlaintext: String?

    public init(
        messageId: Int,
        conversationId: Int,
        newContent: String?,
        isEdited: Bool? = true,
        updateDate: Date? = nil,
        messageDoc: JSONValue? = nil,
        messagePlaintext: String? = nil
    ) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.newContent = newContent
        self.isEdited = isEdited
        self.updateDate = updateDate
        self.messageDoc = messageDoc
        self.messagePlaintext = messagePlaintext
    }
}

/// `ReceiveMessageDelete`. Render a localized placeholder, never the server literal.
public struct MessageDeleteEvent: Codable, Sendable, Equatable {
    public var messageId: Int
    public var conversationId: Int
    public var deletedAt: Date?
    public var isDeleted: Bool?

    public init(messageId: Int, conversationId: Int, deletedAt: Date? = nil, isDeleted: Bool? = true) {
        self.messageId = messageId
        self.conversationId = conversationId
        self.deletedAt = deletedAt
        self.isDeleted = isDeleted
    }
}

/// `ConversationCallStateChanged`. Live only for `Initiated`/`Active`/`Rejoined`; `End` and
/// anything unrecognised are not live (gap G-10, 11 §2.19).
public struct CallStateChangedEvent: Codable, Sendable, Equatable {
    public var conversationId: Int
    public var roomId: String?
    public var status: CallRecordStatus?
    public var startTime: Date?

    public var isLive: Bool { status?.isLive ?? false }

    public init(conversationId: Int, roomId: String?, status: CallRecordStatus?, startTime: Date? = nil) {
        self.conversationId = conversationId
        self.roomId = roomId
        self.status = status
        self.startTime = startTime
    }
}

/// `RemoveAdHocFromConversation`.
public struct RemoveAdHocEvent: Codable, Sendable, Equatable {
    public var conversationId: Int
    public var roomId: String?

    public init(conversationId: Int, roomId: String?) {
        self.conversationId = conversationId
        self.roomId = roomId
    }
}

/// `EventNotificationResponse` (`ReceiveNotification`, `receivenotification_web`).
public struct EventNotificationResponse: Codable, Sendable, Equatable {
    public var id: Int64?
    public var type: String?
    public var status: String?
    public var title: String?
    public var message: String?
    public var allowApproval: Bool?
    public var actionLabel: String?
    public var actionUrl: String?
    public var createdAt: Date?
    public var read: Bool?
}

/// Video hub events the chat surface may react to (hub.md §4).
public enum VideoHubEvent: Sendable, Equatable {
    case groupCallInvite(GroupCallInvite)
    case externalGroupCallInvite(GroupCallInvite)
    case callRejected(roomId: String?, callerId: String?)
    /// Media-plane events (publishers, feeds, screen share), kept raw for a future call screen.
    case media(target: String, payload: JSONValue)
}

/// `ReceiveGroupCallInviteResponse`; note the server's `calenderEventId` spelling.
public struct GroupCallInvite: Codable, Sendable, Equatable {
    public var currentUserId: String?
    public var callerDisplayName: String?
    public var roomId: String?
    public var calenderEventId: String?
    public var conversationId: Int?
    public var callerId: String?
}
