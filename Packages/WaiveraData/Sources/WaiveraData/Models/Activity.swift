import Foundation
import WaiveraAPI

/// A mention, thread reply or reaction in the activity feed (06 §A).
public struct ActivityItem: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case mention, threadReply, reaction, unknown
    }

    public var id: Int64
    public var kind: Kind
    public var actorUserId: String?
    public var actorDisplayName: String?
    public var conversationId: Int
    public var messageId: Int
    public var threadRootMessageId: Int?
    public var reactionType: String?
    /// The server's summary; for reactions the screen builds its own sentence instead.
    public var summary: String?
    public var createdAt: Date?
    public var isRead: Bool

    public init(id: Int64, kind: Kind, conversationId: Int, messageId: Int, isRead: Bool = false) {
        self.id = id
        self.kind = kind
        self.conversationId = conversationId
        self.messageId = messageId
        self.isRead = isRead
    }

    public var destination: ChatDestination {
        if let root = threadRootMessageId, root != messageId {
            return .thread(rootMessageId: root, conversationId: conversationId, targetMessageId: messageId)
        }
        return .conversation(id: conversationId, targetMessageId: messageId)
    }
}

/// The feed plus paging state.
public struct ActivityFeed: Sendable, Hashable {
    public var items: [ActivityItem]
    public var hasMore: Bool
    public var isLoadingMore: Bool
    /// The last `loadMore` failed. The loaded pages stay as they are (the feed's phase is not
    /// touched) and the next `loadMore` retries just that page; cleared when a page arrives.
    public var loadMoreError: WaiveraError?

    public init(
        items: [ActivityItem] = [],
        hasMore: Bool = false,
        isLoadingMore: Bool = false,
        loadMoreError: WaiveraError? = nil
    ) {
        self.items = items
        self.hasMore = hasMore
        self.isLoadingMore = isLoadingMore
        self.loadMoreError = loadMoreError
    }

    public var unreadCount: Int { items.filter { !$0.isRead }.count }
}

/// A saved message and where it opens.
public struct Bookmark: Sendable, Hashable, Identifiable {
    public var message: ChatMessage
    public var id: Int { message.id }
    public var destination: ChatDestination { ChatDestination(message: message) }

    public init(message: ChatMessage) {
        var message = message
        message.isBookmarked = true
        self.message = message
    }
}

/// Bookmarks plus whether they came from the slow per-conversation fallback (gap G-04).
public struct BookmarkList: Sendable, Hashable {
    public var bookmarks: [Bookmark]
    public var usedFallback: Bool

    public init(bookmarks: [Bookmark] = [], usedFallback: Bool = false) {
        self.bookmarks = bookmarks
        self.usedFallback = usedFallback
    }
}
