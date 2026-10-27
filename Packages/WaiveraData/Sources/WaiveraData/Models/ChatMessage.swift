import Foundation
import WaiveraAPI

/// One server message. Built only through `ChatMapper`, which applies the union of every
/// endpoint's aliases and defaults (02 §3, 05 §4).
public struct ChatMessage: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case user, system, channelEvent, unknown
    }

    public var id: Int
    public var clientMessageId: String?
    public var conversationId: Int
    public var author: ChatUser?
    /// Backend user id of the author (or a `bot:` id).
    public var authorId: String?
    /// Compared against the backend user id only (PLAN parity fix).
    public var isMine: Bool
    /// UTC instant; `nil` when the server sent none.
    public var createdAt: Date?
    public var kind: Kind
    public var doc: JSONValue?
    public var plaintext: String?
    public var content: String?
    public var isDeleted: Bool
    public var isEdited: Bool
    public var editedAt: Date?
    public var attachment: Attachment?
    public var reactions: [Reaction]
    public var parentMessageId: Int?
    public var threadRootMessageId: Int?
    public var threadReplyCount: Int
    /// `nil` when the endpoint does not report it (gap G-11).
    public var isBookmarked: Bool?
    public var callRecordId: Int?
    public var systemEventType: String?
    public var systemEventData: JSONValue?
    public var isBot: Bool
    /// Set only by the realtime path; drives the arrival animation (02 §4).
    public var isNew: Bool

    public init(id: Int, conversationId: Int, isMine: Bool = false, createdAt: Date? = nil) {
        self.id = id
        self.conversationId = conversationId
        self.isMine = isMine
        self.createdAt = createdAt
        kind = .user
        isDeleted = false
        isEdited = false
        reactions = []
        threadReplyCount = 0
        isBot = false
        isNew = false
    }

    /// The text a reader sees: the doc's plain text, else plaintext, else content. `nil` for
    /// deleted messages; the screen shows its own localized placeholder (gap G-11).
    public var bodyText: String? {
        guard !isDeleted else { return nil }
        if let text = RichText.plainText(doc) { return text }
        for candidate in [plaintext, content] {
            if let text = candidate?.trimmed, !text.isEmpty { return text }
        }
        return nil
    }

    public var hasRenderableContent: Bool { bodyText != nil || attachment != nil }

    /// The thread this message belongs to, when it is a reply. Bookmark and activity
    /// navigation use the root, never the direct parent (06 §B2).
    public var threadRootId: Int? {
        let root = threadRootMessageId ?? parentMessageId
        return root == id ? nil : root
    }

    public var isThreadReply: Bool { threadRootId != nil }

    public var isCallLog: Bool { callRecordId != nil || systemEventType?.lowercased().contains("call") == true }

    /// Applies a newer delivery of the same message. Fields the newer payload lacks keep their
    /// current value, so a sparse event never erases a richer cached message (PLAN parity fix).
    public func merging(_ newer: ChatMessage) -> ChatMessage {
        var merged = newer
        merged.clientMessageId = newer.clientMessageId ?? clientMessageId
        merged.author = newer.author ?? author
        merged.authorId = newer.authorId ?? authorId
        merged.isMine = newer.isMine || isMine
        merged.createdAt = newer.createdAt ?? createdAt
        merged.doc = newer.doc ?? doc
        merged.plaintext = newer.plaintext ?? plaintext
        merged.content = newer.content ?? content
        merged.editedAt = newer.editedAt ?? editedAt
        merged.attachment = newer.attachment ?? attachment
        merged.parentMessageId = newer.parentMessageId ?? parentMessageId
        merged.threadRootMessageId = newer.threadRootMessageId ?? threadRootMessageId
        merged.threadReplyCount = max(newer.threadReplyCount, threadReplyCount)
        merged.isBookmarked = newer.isBookmarked ?? isBookmarked
        merged.callRecordId = newer.callRecordId ?? callRecordId
        merged.systemEventType = newer.systemEventType ?? systemEventType
        merged.systemEventData = newer.systemEventData ?? systemEventData
        if newer.reactions.isEmpty, !reactions.isEmpty, !newer.isDeleted {
            merged.reactions = reactions
        }
        if newer.kind == .unknown { merged.kind = kind }
        return merged
    }

    /// Reactions grouped by emoji in first-seen order (03 §13).
    public func reactionGroups(viewerId: String?) -> [ReactionGroup] {
        var order: [String] = []
        var users: [String: [String]] = [:]
        for reaction in reactions {
            let emoji = reaction.emoji.trimmed
            guard !emoji.isEmpty else { continue }
            if users[emoji] == nil { order.append(emoji) }
            users[emoji, default: []].append(reaction.userId)
        }
        return order.map { emoji in
            let ids = users[emoji] ?? []
            return ReactionGroup(emoji: emoji, userIds: ids, includesViewer: viewerId.map(ids.contains) ?? false)
        }
    }
}

public struct Attachment: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case image, file
    }

    /// `attachmentScanStatus` (rest.md §2).
    public enum ScanStatus: String, Codable, Sendable, Hashable {
        case clean, pending, rejected, legacy, unknown
    }

    /// The storage key; download through `AttachmentsRepository` with auth (gap G-15).
    public var url: String
    public var kind: Kind
    public var name: String?
    public var contentType: String?
    public var size: Int64?
    public var scanStatus: ScanStatus

    public init(
        url: String,
        kind: Kind,
        name: String? = nil,
        contentType: String? = nil,
        size: Int64? = nil,
        scanStatus: ScanStatus = .clean
    ) {
        self.url = url
        self.kind = kind
        self.name = name
        self.contentType = contentType
        self.size = size
        self.scanStatus = scanStatus
    }

    /// Branches on the content type first, since `attachmentType` has two vocabularies (G-05).
    static func kind(contentType: String?, type: String?, name: String?) -> Kind {
        if let contentType = contentType?.lowercased(), !contentType.isEmpty {
            return contentType.hasPrefix("image/") ? .image : .file
        }
        if let type = type?.lowercased(), type == "image" || type.hasPrefix("image/") { return .image }
        let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "heic", "webp"]
        if let ext = name?.split(separator: ".").last?.lowercased(), imageExtensions.contains(ext) { return .image }
        return .file
    }
}

public struct Reaction: Codable, Sendable, Hashable {
    public var userId: String
    public var fullName: String?
    public var emoji: String

    public init(userId: String, fullName: String? = nil, emoji: String) {
        self.userId = userId
        self.fullName = fullName
        self.emoji = emoji
    }

    /// The fixed set offered in the action sheet (03 §13).
    public static let palette = ["👍", "❤️", "😂", "😮", "😢", "😠"]
}

public struct ReactionGroup: Sendable, Hashable {
    public var emoji: String
    public var userIds: [String]
    public var includesViewer: Bool
    public var count: Int { userIds.count }
}
