import Foundation
import Observation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// The message actions both the conversation and the thread offer (04 §1: threads get the full
/// set). Owns the long-press focus overlay, the open sheet, the toast and prepared files. Every
/// action is `async` so a test can await it; views call them from a `Task`.
@MainActor
@Observable
final class MessageInteractions {
    /// The message lifted in the long-press focus overlay (spec §9.1). It replaces the old actions
    /// sheet, whose actions a long message pushed out of reach (wave 28 B1).
    var focus: MessageActionsModel?
    var sheet: ChatSheet?
    var toast: ChatToast?
    /// A downloaded attachment waiting for the share sheet or "Save to Files".
    var preparedFile: PreparedFile?

    @ObservationIgnored private let actions: (any MessageActions)?
    @ObservationIgnored private let bookmarks: (any BookmarksRepository)?
    @ObservationIgnored private let attachments: (any AttachmentsRepository)?
    @ObservationIgnored private let platform: ChatPlatform
    @ObservationIgnored private let conversationId: Int
    @ObservationIgnored private let isConnected: @MainActor () -> Bool
    @ObservationIgnored private let wait: @MainActor (TimeInterval) async -> Void
    @ObservationIgnored private var nextToastId = 0

    init(
        conversationId: Int,
        actions: (any MessageActions)?,
        bookmarks: (any BookmarksRepository)?,
        attachments: (any AttachmentsRepository)?,
        platform: ChatPlatform,
        isConnected: @escaping @MainActor () -> Bool,
        wait: @escaping @MainActor (TimeInterval) async -> Void = { try? await Task.sleep(for: .seconds($0)) }
    ) {
        self.conversationId = conversationId
        self.actions = actions
        self.bookmarks = bookmarks
        self.attachments = attachments
        self.platform = platform
        self.isConnected = isConnected
        self.wait = wait
    }

    /// Lifts the message into the focus overlay. Silent: no haptic (spec §3).
    func openActions(_ model: MessageActionsModel) {
        focus = model
    }

    /// Closes the focus overlay: a scrim tap, back, or an action that leads elsewhere.
    func closeFocus() {
        focus = nil
    }

    func dismissSheet() {
        sheet = nil
        preparedFile = nil
    }

    /// The overlay stays open and the row pops into a check reading "Copied"; the overlay then
    /// closes on its own after `ChatMetrics.focusCopiedHold`.
    func copy(_ message: ChatMessage) {
        let text = message.copyableText
        guard !text.isEmpty else { return }
        platform.copy(text)
        if var model = focus, model.message.id == message.id {
            model.copied = true
            focus = model
        }
    }

    /// Called by the overlay once "Copied" has shown for its beat.
    func finishCopy(messageId: Int) {
        guard let model = focus, model.message.id == messageId, model.copied else { return }
        focus = nil
    }

    /// Reversible, so it offers Undo instead of asking first.
    func toggleBookmark(messageId: Int) async {
        focus = nil
        sheet = nil
        guard let bookmarks else { return }
        do {
            let saved = try await bookmarks.toggle(messageId: messageId, conversationId: conversationId)
            show(saved ? .bookmarkSaved(messageId: messageId) : .bookmarkRemoved(messageId: messageId))
        } catch {
            fail(.bookmark, error)
        }
    }

    func undoBookmark(messageId: Int) async {
        guard let bookmarks else { return }
        do {
            _ = try await bookmarks.toggle(messageId: messageId, conversationId: conversationId)
        } catch {
            fail(.bookmark, error)
        }
    }

    /// The overlay closes first; the confirmation follows once it has gone
    /// (`MotionTiming.focusCloseWait`), so the two never present over each other.
    func requestDelete(messageId: Int) async {
        let fromFocus = focus != nil
        focus = nil
        if fromFocus {
            await wait(MotionTiming.focusCloseWait)
            guard focus == nil, sheet == nil else { return }
        }
        sheet = .confirmDelete(messageId: messageId)
    }

    func confirmDelete(messageId: Int) async {
        sheet = nil
        guard let actions else { return }
        do {
            try await actions.delete(messageId: messageId, conversationId: conversationId)
        } catch {
            fail(.delete, error)
        }
    }

    /// Hub only (G-01): without a live connection nothing changes locally.
    func react(messageId: Int, emoji: String) async {
        if focus?.message.id == messageId { focus = nil }
        guard isConnected() else {
            needsConnection()
            return
        }
        guard let actions else { return }
        do {
            try await actions.toggleReaction(emoji, messageId: messageId, conversationId: conversationId)
        } catch WaiveraError.realtimeUnavailable {
            needsConnection()
        } catch {
            fail(.reaction, error)
        }
    }

    func openReactionDetails(messageId: Int, emoji: String) {
        sheet = .reactions(messageId: messageId, initialEmoji: emoji)
    }

    func openAttachment(_ message: ChatMessage) {
        guard let attachment = message.attachment else { return }
        guard attachment.scanStatus != .rejected, attachment.scanStatus != .pending else { return }
        if AttachmentRules.isImage(attachment) {
            sheet = .imagePreview(messageId: message.id)
        } else {
            sheet = .fileActions(
                messageId: message.id,
                fileName: AttachmentRules.fileName(attachment, messageId: message.id),
                isBusy: false
            )
        }
    }

    func prepareFile(_ message: ChatMessage, purpose: PreparedFile.Purpose) async {
        guard let attachment = message.attachment,
            case .fileActions(let messageId, let fileName, let isBusy) = sheet, messageId == message.id, !isBusy
        else { return }
        sheet = .fileActions(messageId: messageId, fileName: fileName, isBusy: true)
        defer {
            if case .fileActions(let id, let name, true) = sheet, id == messageId {
                sheet = .fileActions(messageId: id, fileName: name, isBusy: false)
            }
        }
        do {
            let data = try await download(messageId: messageId)
            let url = try AttachmentFiles.write(data, fileName: fileName)
            preparedFile = PreparedFile(
                url: url,
                fileName: fileName,
                mimeType: AttachmentRules.mimeType(attachment, messageId: messageId),
                purpose: purpose
            )
        } catch {
            fail(purpose == .save ? .fileSave : .fileOpen, error)
        }
    }

    /// From the share sheet or the document picker. A cancelled save is silent (03 §8).
    func finishPreparedFile(completed: Bool) {
        guard let file = preparedFile else { return }
        preparedFile = nil
        guard completed else { return }
        sheet = nil
        if file.purpose == .save {
            show(.fileSaved(name: file.fileName))
        }
    }

    /// The image preview and inline images load through here: one retry, except for a file
    /// that failed security scanning (03 §8, G-15).
    func download(messageId: Int) async throws -> Data {
        guard let attachments else { throw WaiveraError.configurationMissing }
        do {
            return try await attachments.data(forMessageId: messageId)
        } catch WaiveraError.attachmentBlocked {
            throw WaiveraError.attachmentBlocked
        } catch {
            return try await attachments.data(forMessageId: messageId)
        }
    }

    func retry(clientMessageId: String) async {
        await actions?.retry(clientMessageId: clientMessageId)
    }

    func discard(clientMessageId: String) async {
        await actions?.discard(clientMessageId: clientMessageId)
    }

    func openLink(_ url: URL) {
        guard let safe = SafeLinks.url(url.absoluteString) else { return }
        platform.openInApp(safe)
    }

    func fail(_ action: ChatToast.FailedAction, _ error: (any Error)?) {
        show(.failed(action, detail: error.map(WaiveraError.from)))
    }

    func dismissToast() { toast = nil }

    private func needsConnection() {
        show(.failed(.reactionNeedsConnection, detail: nil))
    }

    private func show(_ kind: ChatToast.Kind) {
        nextToastId += 1
        toast = ChatToast(id: nextToastId, kind: kind)
    }
}

/// Temporary copies of attachments for Share and Save. One folder, emptied before each copy,
/// so shared files never pile up, and on sign-out, so none outlives the session (AS-10).
public enum AttachmentFiles {
    static let directoryName = "waivera-chat-share"

    static var directory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Deletes every shared copy. The app calls it whenever the session ends.
    public static func removeAll() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        for item in (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [] {
            try? manager.removeItem(at: item)
        }
    }

    static func write(_ data: Data, fileName: String) throws -> URL {
        let manager = FileManager.default
        removeAll()
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(AttachmentRules.sanitizedFileName(fileName))
        try data.write(to: url, options: [.atomic])
        return url
    }
}
