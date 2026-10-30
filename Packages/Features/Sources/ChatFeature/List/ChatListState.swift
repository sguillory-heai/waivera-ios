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

/// The typing preview split where the name ends, so a one-line row cuts the name and keeps
/// "is typing…" whole (Android `TypingLine`).
struct TypingParts: Sendable, Hashable {
    var names: String
    var rest: String
}

/// One inbox row, fully resolved so the row view does no formatting in `body`.
struct ChatRow: Identifiable, Sendable, Hashable {
    let id: Int
    var title: String
    /// The name inside a group's composed `title` ("Priya Raman" in "Priya Raman & 2 others"):
    /// the only part a one-line title may cut, so the count always shows. `nil` for other titles.
    var titleName: String?
    /// The count in short ("+4"), shown in place of "& 4 others" when even that does not fit.
    var titleCompactCount: String?
    var leading: RowLeading
    var preview: String
    var previewKind: PreviewKind
    /// "You" or the author's first name in groups and channels.
    var senderPrefix: String?
    /// Replaces the preview while someone types.
    var typingLabel: String?
    /// Where the name ends in `typingLabel`, in characters; `nil` when no single name shows.
    var typingNamesEnd: Int?
    var timeLabel: String
    var unreadCount: Int
    var hasAttachment: Bool
    var isChannel: Bool
    var isReadOnly: Bool
    var isCallLive: Bool
    var isOpeningCall: Bool
    /// Non-nil while the arrival wash plays for this message id.
    var arrivalKey: Int?
    /// A message of mine here never went out; the row says "Not sent" in place of the preview.
    var isSendFailed = false
    /// Everything VoiceOver reads for the row, in one sentence.
    var accessibilityText: String

    var isUnread: Bool { unreadCount > 0 }

    /// The typing line in two pieces, or `nil` when there is no name to cut.
    var typingParts: TypingParts? {
        guard let typingLabel, let end = typingNamesEnd, end > 0, end <= typingLabel.count else { return nil }
        let split = typingLabel.index(typingLabel.startIndex, offsetBy: end)
        return TypingParts(names: String(typingLabel[..<split]), rest: String(typingLabel[split...]))
    }

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
        /// Mark as read did not reach the server, so the badge came back; Retry sends it again.
        case markReadFailed(conversationId: Int)
    }

    /// The banner copy's string key.
    var messageKey: String {
        switch kind {
        case .callFailed: "chat.list.call.failed"
        case .markReadFailed: "chat.list.markRead.failed"
        }
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
