import Foundation

/// Mirrors `SendMessageRequest` (`POST /api/chat/send`).
public struct SendMessageRequest: Codable, Sendable, Equatable {
    public var conversationId: Int
    /// Idempotency key; the server returns the committed message on a retry.
    public var clientMessageId: String?
    public var recipientId: String?
    public var text: String?
    /// `documentUrl` from `/api/chat/upload-attachment`.
    public var attachmentUrl: String?
    public var doc: JSONValue?
    public var parentMessageId: Int?

    public init(
        conversationId: Int,
        clientMessageId: String?,
        text: String?,
        doc: JSONValue?,
        attachmentUrl: String? = nil,
        parentMessageId: Int? = nil
    ) {
        self.conversationId = conversationId
        self.clientMessageId = clientMessageId
        self.text = text
        self.doc = doc
        self.attachmentUrl = attachmentUrl
        self.parentMessageId = parentMessageId
    }
}

/// Mirrors `CreateConversationRequest`.
public struct CreateConversationRequest: Codable, Sendable, Equatable {
    public var participantIds: [String]

    public init(participantIds: [String]) {
        self.participantIds = participantIds
    }
}

/// Mirrors `ChatReadThroughRequest`.
public struct ChatReadThroughRequest: Codable, Sendable, Equatable {
    public var lastVisibleMessageId: Int
    public var threadRootMessageId: Int?

    public init(lastVisibleMessageId: Int, threadRootMessageId: Int?) {
        self.lastVisibleMessageId = lastVisibleMessageId
        self.threadRootMessageId = threadRootMessageId
    }
}

/// The read-through response and hub `ReceiveChatReadState` payload.
/// `conversationId == 0` means "mark every id in `readActivityIds` read" (read-all).
public struct ChatReadState: Codable, Sendable, Equatable {
    public var conversationId: Int
    public var lastVisibleMessageId: Int?
    public var threadRootMessageId: Int?
    public var readActivityIds: [Int64]?
    public var readAt: Date?

    public init(
        conversationId: Int,
        lastVisibleMessageId: Int?,
        threadRootMessageId: Int?,
        readActivityIds: [Int64]?,
        readAt: Date?
    ) {
        self.conversationId = conversationId
        self.lastVisibleMessageId = lastVisibleMessageId
        self.threadRootMessageId = threadRootMessageId
        self.readActivityIds = readActivityIds
        self.readAt = readAt
    }
}

/// Mirrors `EditMessageRequest`.
public struct EditMessageRequest: Codable, Sendable, Equatable {
    public var newContent: String?
    public var doc: JSONValue?

    public init(newContent: String?, doc: JSONValue?) {
        self.newContent = newContent
        self.doc = doc
    }
}

/// Mirrors `ChatActivityResponse`; also the hub `ReceiveChatActivity` payload.
public struct ChatActivityResponse: Codable, Sendable, Hashable {
    public enum ActivityType: String, OpenEnum {
        case mention = "chat.mention"
        case threadReply = "chat.thread_reply"
        case reaction = "chat.reaction"
        case unknown = "UNKNOWN"
        public static var unknownCase: ActivityType { .unknown }
    }

    public var id: Int64
    public var activityType: ActivityType?
    public var actorUserId: String?
    public var actorDisplayName: String?
    public var conversationId: Int
    public var messageId: Int
    public var threadRootMessageId: Int?
    public var reactionType: String?
    public var summary: String?
    public var createdAt: Date?
    public var read: Bool?
}

/// The bare upload response from `POST /api/chat/upload-attachment`.
public struct ChatAttachmentUploadResponse: Codable, Sendable, Equatable {
    /// Storage key to pass back as `attachmentUrl`; not a URL.
    public var documentUrl: String
    public var uploadId: String?
    public var originalName: String?
    public var contentType: String?
    public var size: Int64?
    public var scanStatus: String?
    public var sha256: String?
}

/// Mirrors `Base64AvatarResultDto` (`GET /api/file/avatar/{userId}`).
public struct Base64AvatarResultDto: Codable, Sendable, Equatable {
    /// A full data URI, `data:image/png;base64,…`.
    public var base64Image: String?
    public var expiresInSeconds: Int?

    /// The decoded image bytes, or `nil` when the URI is not base64 data.
    public var imageData: Data? {
        guard let base64Image, let comma = base64Image.firstIndex(of: ",") else { return nil }
        let header = base64Image[..<comma]
        guard header.hasPrefix("data:"), header.hasSuffix(";base64") else { return nil }
        return Data(base64Encoded: String(base64Image[base64Image.index(after: comma)...]))
    }
}

/// Mirrors `CreateMeetingRoomRequest`.
public struct CreateMeetingRoomRequest: Codable, Sendable, Equatable {
    public var calendarEventId: String?
    public var conversationId: Int?

    public init(calendarEventId: String?, conversationId: Int?) {
        self.calendarEventId = calendarEventId
        self.conversationId = conversationId
    }
}

/// Mirrors `CreateMeetingRoomResponse`.
public struct CreateMeetingRoomResponse: Codable, Sendable, Equatable {
    public var message: String?
    public var roomId: String?
    public var meetingRoomId: String?
    public var calendarEventId: String?
    public var conversationId: Int?
    public var reused: Bool?
    public var isPublisher: Bool?
}
