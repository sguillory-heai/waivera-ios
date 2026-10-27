import Foundation
import WaiveraAPI

/// One inbox row and the conversation screen's metadata.
public struct Conversation: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case direct, group, channel, bot
    }

    public var id: Int
    public var kind: Kind
    /// Backend id of the signed-in user, so titles and peers can exclude them.
    public var viewerId: String
    public var participants: [ChatUser]
    public var channel: ChannelInfo?
    public var lastMessage: ChatMessage?
    public var unreadCount: Int
    public var lastReadAt: Date?
    public var activeCall: CallRoom?
    public var isArchived: Bool
    /// `canWrite` as reported for non-channels; `nil` means writable (02 §4).
    public var reportedCanWrite: Bool?

    public init(id: Int, kind: Kind, viewerId: String, participants: [ChatUser] = []) {
        self.id = id
        self.kind = kind
        self.viewerId = viewerId
        self.participants = participants
        unreadCount = 0
        isArchived = false
    }

    public var others: [ChatUser] { participants.filter { $0.id != viewerId } }

    /// The person a direct conversation is with.
    public var peer: ChatUser? { others.first ?? participants.first }

    public var title: ConversationTitle {
        switch kind {
        case .channel:
            return .channel(name: channel?.name?.trimmed.nilIfEmpty)
        case .bot:
            return .bot
        case .direct, .group:
            let others = others
            guard let first = others.first else { return .untitled }
            if others.count == 1 { return .person(name: first.fullName) }
            return .group(firstName: first.compactName, otherCount: others.count - 1)
        }
    }

    /// Channels must be explicitly writable and not archived; bots are never writable.
    public var canWrite: Bool {
        switch kind {
        case .bot: false
        case .channel: channel?.canWrite == true && channel?.isArchived != true && !isArchived
        case .direct, .group: reportedCanWrite != false
        }
    }

    public var preview: ConversationPreview { ConversationPreview(lastMessage) }

    /// Sort key for the inbox, newest first.
    public var activityDate: Date? { lastMessage?.createdAt ?? lastReadAt }

    /// Applies a newer copy (detail fetch, list refresh) without losing what only the older
    /// copy knew: attachment fields on the preview (G-05) and the live unread count (G-14).
    public func merging(detail newer: Conversation, keepUnread: Bool) -> Conversation {
        var merged = newer
        merged.channel = newer.channel ?? channel
        if newer.participants.isEmpty { merged.participants = participants }
        merged.lastMessage = Self.mergedPreview(current: lastMessage, newer: newer.lastMessage)
        if keepUnread { merged.unreadCount = unreadCount }
        merged.activeCall = newer.activeCall ?? activeCall
        return merged
    }

    static func mergedPreview(current: ChatMessage?, newer: ChatMessage?) -> ChatMessage? {
        guard let newer else { return current }
        guard let current else { return newer }
        if current.id == newer.id { return current.merging(newer) }
        if let currentDate = current.createdAt, let newerDate = newer.createdAt, newerDate < currentDate {
            return current
        }
        return newer
    }
}

public struct ChannelInfo: Codable, Sendable, Hashable {
    public var channelId: String?
    public var name: String?
    public var topic: String?
    public var type: String?
    public var isArchived: Bool?
    public var canWrite: Bool?

    public init(
        channelId: String? = nil,
        name: String? = nil,
        topic: String? = nil,
        type: String? = nil,
        isArchived: Bool? = nil,
        canWrite: Bool? = nil
    ) {
        self.channelId = channelId
        self.name = name
        self.topic = topic
        self.type = type
        self.isArchived = isArchived
        self.canWrite = canWrite
    }
}

/// A live call or meeting room on a conversation (gap G-10: only Initiated/Active/Rejoined).
public struct CallRoom: Codable, Sendable, Hashable {
    public var roomId: String
    public var calendarEventId: String?
    public var startedAt: Date?

    public init(roomId: String, calendarEventId: String? = nil, startedAt: Date? = nil) {
        self.roomId = roomId
        self.calendarEventId = calendarEventId
        self.startedAt = startedAt
    }
}

/// Semantic title; the screen picks the localized copy ("Channel", "Waivera", "A & 2 others").
public enum ConversationTitle: Sendable, Hashable {
    case channel(name: String?)
    case bot
    case person(name: String?)
    case group(firstName: String?, otherCount: Int)
    case untitled
}

/// Semantic inbox preview (02 §4); the screen localizes every case except `.text`.
public enum ConversationPreview: Sendable, Hashable {
    case noMessages
    case text(String)
    case photo
    case file(name: String?)
    case systemUpdate
    case deleted
    /// Nothing renderable yet; the list hydrates it from the detail endpoint.
    case blank

    init(_ message: ChatMessage?) {
        guard let message else {
            self = .noMessages
            return
        }
        if message.isDeleted {
            self = .deleted
        } else if let text = message.bodyText {
            let firstLine =
                text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n")
                .first?.collapsedWhitespace ?? ""
            self = firstLine.isEmpty ? .blank : .text(firstLine)
        } else if let attachment = message.attachment {
            self = attachment.kind == .image ? .photo : .file(name: attachment.name?.trimmed.nilIfEmpty)
        } else if message.kind != .user {
            self = .systemUpdate
        } else {
            self = .blank
        }
    }

    public var needsHydration: Bool { self == .blank }
}

extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
