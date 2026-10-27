import Foundation
import WaiveraAPI

/// `All | Unread | Channels` (02 §1.4).
enum ChatListFilter: String, CaseIterable, Sendable, Hashable {
    case all, unread, channels
}

/// Why the list is empty; each reason has its own copy (02 §5).
enum ChatListEmptyReason: Sendable, Hashable {
    case noMatches, allCaughtUp, noChannels, noConversations
}

/// The connection pill under the title (02 §1.2).
enum ConnectionIndicator: Sendable, Hashable {
    case online, connecting, reconnecting, offline
}

/// What leads a row: a tile for channels, bots and groups, an avatar for a direct chat.
enum RowLeading: Sendable, Hashable {
    case channel(archived: Bool)
    case bot
    case group
    /// `userId` is the backend id, used for the avatar and "View profile".
    case direct(userId: String?, name: String)
}

/// How the preview line was produced; placeholders and system rows render in italics.
enum PreviewKind: Sendable, Hashable {
    case text, attachment, system, placeholder
    /// Nothing renderable yet; the data layer fills it from the detail endpoint.
    case blank
}

/// One inbox row, fully resolved so the row view does no formatting in `body`.
struct ChatRow: Identifiable, Sendable, Hashable {
    let id: Int
    var title: String
    var leading: RowLeading
    var preview: String
    var previewKind: PreviewKind
    /// "You" or the author's first name in groups and channels.
    var senderPrefix: String?
    /// Replaces the preview while someone types.
    var typingLabel: String?
    var timeLabel: String
    var unreadCount: Int
    var hasAttachment: Bool
    var isChannel: Bool
    var isReadOnly: Bool
    var isCallLive: Bool
    var isOpeningCall: Bool
    /// Non-nil while the arrival wash plays for this message id.
    var arrivalKey: Int?
    /// Everything VoiceOver reads for the row, in one sentence.
    var accessibilityText: String

    var isUnread: Bool { unreadCount > 0 }

    /// "View profile" is offered for direct chats with a known person.
    var profileUserId: String? {
        guard case .direct(let userId?, _) = leading, !userId.isEmpty else { return nil }
        return userId
    }
}

enum ChatListContent: Sendable, Hashable {
    /// Nothing cached and the first fetch is running; the skeleton shows after ~300 ms.
    case loading
    /// Nothing cached and the fetch failed.
    case error(WaiveraError)
    case empty(ChatListEmptyReason)
    case rows
}

/// A transient message over the list, with an optional retry.
struct ChatListNotice: Identifiable, Sendable, Hashable {
    enum Kind: Sendable, Hashable {
        /// The web lobby could not be opened; Retry tries again.
        case callFailed(conversationId: Int)
    }

    let id: UUID
    let kind: Kind

    init(_ kind: Kind, id: UUID = UUID()) {
        self.kind = kind
        self.id = id
    }
}

struct ChatListState: Sendable, Hashable {
    var content: ChatListContent = .loading
    var rows: [ChatRow] = []
    var connection: ConnectionIndicator = .connecting
    /// A refresh failed while cached rows are on screen.
    var refreshError: WaiveraError?
    /// The person scrolled down and newer activity is waiting; rows keep their place until
    /// they return to the top or tap the pill, so the list never jumps under them.
    var hasPendingReorder = false
    var notice: ChatListNotice?
}
