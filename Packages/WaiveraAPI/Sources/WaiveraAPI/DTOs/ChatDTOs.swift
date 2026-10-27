import Foundation

/// Mirrors `UserInfoResponse`. Also used for chat authors: the fat `MessageAuthorResponse`
/// and EF `User` payloads (gap G-04) decode into it and their extra members are ignored.
/// Never trust `deactivated`/`joinDate` on a chat author.
public struct UserInfoResponse: Codable, Sendable, Hashable {
    public var id: String?
    public var firstName: String?
    public var lastName: String?
    public var email: String?
    public var displayName: String?
    public var scId: String?
    public var isParticipant: Bool?
    public var isExternal: Bool?
    public var avatarUrl: String?
    public var employeeRole: String?

    public init(
        id: String?,
        firstName: String? = nil,
        lastName: String? = nil,
        email: String? = nil,
        displayName: String? = nil,
        avatarUrl: String? = nil
    ) {
        self.id = id
        self.firstName = firstName
        self.lastName = lastName
        self.email = email
        self.displayName = displayName
        self.avatarUrl = avatarUrl
    }
}

/// Mirrors `ReactionResponse`.
public struct ReactionResponse: Codable, Sendable, Hashable {
    public var id: Int?
    public var userId: String?
    public var fullName: String?
    public var reactionType: String?

    public init(id: Int?, userId: String?, fullName: String?, reactionType: String?) {
        self.id = id
        self.userId = userId
        self.fullName = fullName
        self.reactionType = reactionType
    }
}

/// `SD.MessageType`. Sent as a string on both transports.
public enum MessageType: String, OpenEnum {
    case user = "USER"
    case system = "SYSTEM"
    case channelEvent = "CHANNEL_EVENT"
    case unknown = "UNKNOWN"
    public static var unknownCase: MessageType { .unknown }
}

/// Union of `MessageSendResponse`, `MessageResponse` and `LastMessageDto`. Each endpoint
/// fills a different subset (rest.md §2), so every field except the ids is optional.
public struct MessageSendResponse: Codable, Sendable, Hashable {
    public var id: Int
    public var clientMessageId: String?
    public var author: UserInfoResponse?
    /// `LastMessageDto` only: the author id (no author object, gap G-05).
    public var userId: String?
    public var botId: String?
    public var conversationId: Int?
    public var messageContent: String?
    public var createDate: Date?
    public var attachmentUrl: String?
    public var attachmentType: String?
    public var attachmentOriginalName: String?
    /// Older payloads name the file `attachmentName`.
    public var attachmentName: String?
    public var attachmentContentType: String?
    public var attachmentSize: Int64?
    public var attachmentScanStatus: String?
    public var messageType: MessageType?
    public var reactions: [ReactionResponse]?
    public var callRecordId: Int?
    public var isBot: Bool?
    public var systemEventType: String?
    public var systemEventData: JSONValue?
    public var isEdited: Bool?
    public var updateDate: Date?
    public var isDeleted: Bool?
    public var deletedAt: Date?
    public var isBookmarked: Bool?
    /// `0` plain text, `1` rich text.
    public var contentFormat: Int?
    /// A parsed doc on message endpoints; a JSON **string** on `/api/chat/all` (gap G-05).
    /// Use `parsedMessageDoc`.
    public var messageDoc: JSONValue?
    public var messagePlaintext: String?
    public var parentMessageId: Int?
    public var threadRootMessageId: Int?
    public var threadReplyCount: Int?

    public init(id: Int, conversationId: Int?) {
        self.id = id
        self.conversationId = conversationId
    }

    /// `messageDoc` as an object, re-parsing the stringified form `/api/chat/all` sends.
    public var parsedMessageDoc: JSONValue? {
        switch messageDoc {
        case .string(let raw):
            guard let data = raw.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: data)
        case .object:
            return messageDoc
        default:
            return nil
        }
    }

    /// Author id from `author.id`, falling back to `LastMessageDto.userId`/`botId`.
    public var authorId: String? {
        author?.id ?? userId ?? botId.map { $0.hasPrefix("bot:") ? $0 : "bot:\($0)" }
    }
}

/// Mirrors `ChannelDto`. `channelType` is a string over REST and an integer on the hub.
public struct ChannelDto: Codable, Sendable, Hashable {
    public enum ChannelType: String, OpenEnum {
        case company = "COMPANY"
        case team = "TEAM"
        case custom = "CUSTOM"
        case unknown = "UNKNOWN"
        public static var unknownCase: ChannelType { .unknown }
        public static var integerCases: [ChannelType] { [.company, .team, .custom] }
    }

    public var channelId: String?
    public var conversationId: Int?
    public var name: String?
    public var topic: String?
    public var channelType: ChannelType?
    public var associatedEntityId: String?
    public var ownerId: String?
    public var isArchived: Bool?
    public var canWrite: Bool?
}

/// Mirrors `ConversationMeetingRoomDto`.
public struct ConversationMeetingRoomDto: Codable, Sendable, Hashable {
    public var id: String?
    public var roomId: String?
    public var calendarEventId: String?
    public var createdAt: Date?
    public var startDate: Date?
    public var title: String?
}

/// `CALL_RECORD_STATUS`; anything other than the live members is not a live call (G-10).
public enum CallRecordStatus: String, OpenEnum {
    case initiated = "Initiated"
    case active = "Active"
    case rejoined = "Rejoined"
    case end = "End"
    case unknown = "UNKNOWN"
    public static var unknownCase: CallRecordStatus { .unknown }

    public var isLive: Bool { self == .initiated || self == .active || self == .rejoined }
}

/// Mirrors `OngoingCallDto`.
public struct OngoingCallDto: Codable, Sendable, Hashable {
    public var roomId: String?
    public var startTime: Date?
    public var status: CallRecordStatus?
    public var callRecordId: Int?
}

/// Mirrors `ConversationResponse` (`my-conversations`, `conversation/{id}`, `create-conversation`,
/// hub `ConversationCreated`) and `UnifiedConversationResponse` (`/api/chat/all`, keyed by
/// `conversationId`, gap G-05). `id` is filled from whichever key is present.
public struct ConversationResponse: Codable, Sendable, Hashable {
    public var id: Int
    public var isBotDirect: Bool?
    public var participants: [UserInfoResponse]?
    public var lastMessage: MessageSendResponse?
    public var lastReadAt: Date?
    public var unreadCount: Int?
    public var isChannel: Bool?
    public var channel: ChannelDto?
    public var activeMeeting: ConversationMeetingRoomDto?
    public var ongoingCall: OngoingCallDto?

    enum CodingKeys: String, CodingKey {
        case id, conversationId, isBotDirect, participants, lastMessage, lastReadAt, unreadCount
        case isChannel, channel, activeMeeting, ongoingCall
    }

    public init(id: Int) {
        self.id = id
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        guard let id = container.lenientInt(forKey: .id) ?? container.lenientInt(forKey: .conversationId) else {
            throw DecodingError.keyNotFound(CodingKeys.id, .init(codingPath: decoder.codingPath, debugDescription: ""))
        }
        self.id = id
        isBotDirect = container.lenient(Bool.self, forKey: .isBotDirect)
        participants = container.lenientArray(UserInfoResponse.self, forKey: .participants)
        lastMessage = container.lenient(MessageSendResponse.self, forKey: .lastMessage)
        lastReadAt = container.lenient(Date.self, forKey: .lastReadAt)
        unreadCount = container.lenientInt(forKey: .unreadCount)
        isChannel = container.lenient(Bool.self, forKey: .isChannel)
        channel = container.lenient(ChannelDto.self, forKey: .channel)
        activeMeeting = container.lenient(ConversationMeetingRoomDto.self, forKey: .activeMeeting)
        ongoingCall = container.lenient(OngoingCallDto.self, forKey: .ongoingCall)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encodeIfPresent(isBotDirect, forKey: .isBotDirect)
        try container.encodeIfPresent(participants, forKey: .participants)
        try container.encodeIfPresent(lastMessage, forKey: .lastMessage)
        try container.encodeIfPresent(lastReadAt, forKey: .lastReadAt)
        try container.encodeIfPresent(unreadCount, forKey: .unreadCount)
        try container.encodeIfPresent(isChannel, forKey: .isChannel)
        try container.encodeIfPresent(channel, forKey: .channel)
        try container.encodeIfPresent(activeMeeting, forKey: .activeMeeting)
        try container.encodeIfPresent(ongoingCall, forKey: .ongoingCall)
    }
}
