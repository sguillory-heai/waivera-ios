import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// What the action sheet offers for one message (03 §14; threads get the same, 04 §1).
struct MessageActionsModel: Hashable, Sendable {
    var message: ChatMessage
    var rich: RichDocument?
    var canReact: Bool
    var canReply: Bool
    var canEdit: Bool
    var canDelete: Bool
    var canCopy: Bool
    var copied = false
}

/// Which actions a long press offers (03 §14). Threads use the same rules (04 §1).
enum ChatActions {
    /// Pending rows have inline Retry, Edit and Discard instead; deleted and system rows have none.
    static func canOpen(_ message: ChatMessage) -> Bool {
        !message.isDeleted && message.kind == .user
    }

    static func model(
        _ message: ChatMessage,
        viewerId: String?,
        canWrite: Bool?,
        allowsReply: Bool
    ) -> MessageActionsModel {
        let writable = canWrite == true
        let mine = message.isMine || (viewerId != nil && message.authorId == viewerId)
        let hasText = !message.copyableText.isEmpty
        return MessageActionsModel(
            message: message,
            rich: TipTapParser.document(for: message),
            canReact: writable,
            canReply: writable && allowsReply && !message.isThreadReply,
            canEdit: writable && mine && hasText,
            canDelete: writable && mine,
            canCopy: hasText
        )
    }
}

/// The one sheet open over a message list.
enum ChatSheet: Hashable, Sendable, Identifiable {
    case actions(MessageActionsModel)
    case reactions(messageId: Int, initialEmoji: String)
    case fileActions(messageId: Int, fileName: String, isBusy: Bool)
    case imagePreview(messageId: Int)
    case confirmDelete(messageId: Int)

    var id: String {
        switch self {
        case .actions(let model): "actions-\(model.message.id)"
        case .reactions(let messageId, _): "reactions-\(messageId)"
        case .fileActions(let messageId, _, _): "file-\(messageId)"
        case .imagePreview(let messageId): "image-\(messageId)"
        case .confirmDelete(let messageId): "delete-\(messageId)"
        }
    }
}

/// Short feedback over the list. Bookmark changes offer Undo instead of asking first.
struct ChatToast: Hashable, Sendable, Identifiable {
    enum Kind: Hashable, Sendable {
        case bookmarkSaved(messageId: Int)
        case bookmarkRemoved(messageId: Int)
        case fileSaved(name: String)
        /// `detail` is a typed error; its copy is client-owned, never server text.
        case failed(FailedAction, detail: WaiveraError?)
    }

    /// Raw values are the copy keys in `Conversation.strings`.
    enum FailedAction: String, Hashable, Sendable {
        case bookmark = "bookmark.failed"
        case delete = "delete.failed"
        case edit = "edit.failed"
        case reaction = "reaction.failed"
        case reactionNeedsConnection = "reaction.needs.connection"
        case fileSave = "file.save.failed"
        case fileOpen = "file.open.failed"
        case call = "call.open.failed"
        case link = "link.failed"
        case imageUnreadable = "image.unreadable"
    }

    var id: Int
    var kind: Kind
}

/// A programmatic scroll the list performs once per `id`.
struct ScrollCommand: Hashable, Sendable {
    enum Target: Hashable, Sendable {
        case latest
        case key(String)
    }

    var id: Int
    var target: Target
}

/// A file prepared for the share sheet or "Save to Files".
struct PreparedFile: Hashable, Sendable, Identifiable {
    enum Purpose: Hashable, Sendable {
        case share, save
    }

    var url: URL
    var fileName: String
    var mimeType: String
    var purpose: Purpose

    var id: String { "\(purpose)-\(url.path)" }
}

/// Things only the platform can do, injected so the models stay testable on Linux.
struct ChatPlatform {
    var copy: @MainActor (String) -> Void
    var haptic: @MainActor (HapticEvent) -> Void
    /// In-app Safari, for message and ticket links (already checked by `SafeLinks`).
    var openInApp: @MainActor (URL) -> Void
    /// External browser, for the web call lobby (which needs the camera and microphone).
    var openExternally: @MainActor (URL) -> Void

    init(
        copy: @escaping @MainActor (String) -> Void = { _ in },
        haptic: @escaping @MainActor (HapticEvent) -> Void = { _ in },
        openInApp: @escaping @MainActor (URL) -> Void = { _ in },
        openExternally: @escaping @MainActor (URL) -> Void = { _ in }
    ) {
        self.copy = copy
        self.haptic = haptic
        self.openInApp = openInApp
        self.openExternally = openExternally
    }
}

/// An image picked for sending, before it is uploaded.
struct StagedImage: Hashable, Sendable {
    var data: Data
    var fileName: String?
    var mimeType: String
}
