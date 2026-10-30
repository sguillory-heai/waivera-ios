import Foundation
import WaiveraAPI
import WaiveraData

/// What fills the message area. Rows stay on screen through refresh errors (stale, not error).
enum ConversationContent: Equatable, Sendable {
    /// The route carried an id the API can never return (03 §1).
    case invalid
    case loading
    case error(WaiveraError)
    case empty
    case messages
}

/// The header call button and the in-progress banner (03 §1, §19).
struct CallDisplay: Equatable, Sendable {
    var isAvailable = false
    var isLive = false
    var isOpening = false
}

/// Everything the conversation screen draws, in one value so previews and snapshots can set
/// any state directly.
struct ConversationState: Equatable, Sendable {
    var title: ConversationTitle?
    /// Everyone in a group, for the header's "N members" button; `nil` for direct messages,
    /// channels and the bot, which have no members screen (spec §9.2).
    var memberCount: Int?
    var subtitle: ConnectionSubtitle?
    var content: ConversationContent = .loading
    /// Oldest first; the list anchors to the bottom.
    var items: [TimelineItem] = []
    var isStale = false
    var hasOlder = false
    var isLoadingOlder = false
    /// The last older page failed; the top of the list offers Retry instead of loading again.
    var olderFailed = false
    var highlightKey: String?
    var visibleTimestamps: Set<String> = []
    var names: [String: String] = [:]
    var typing: TypingLabel?
    /// `nil` while the conversation loads: the composer stays disabled, no notice yet (03 §18).
    var canWrite: Bool?
    var readOnlyReason: ReadOnlyReason?
    var sendError: SendErrorKind?
    var call = CallDisplay()
    var stagedImage: StagedImage?
    var isUploading = false
    var editingMessageID: Int?
    var scrollCommand: ScrollCommand?
    var viewerId: String?
    var isBotConversation = false
}

extension TimelineItem {
    /// The server message drawn by this row with `messageId`, if any.
    func message(_ messageId: Int) -> ChatMessage? {
        switch self {
        case .message(let row) where row.message.id == messageId: row.message
        case .system(let row) where row.message.id == messageId: row.message
        case .callLog(let row): row.messages.first { $0.id == messageId }
        default: nil
        }
    }
}
