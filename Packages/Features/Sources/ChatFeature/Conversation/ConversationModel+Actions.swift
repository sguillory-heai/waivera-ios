import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// The composer, the row actions and the call handoff.
extension ConversationModel {
    // MARK: Composer

    /// The composer text changed: feeds the throttled typing signal and clears the banner.
    func draftChanged() {
        if state.sendError != nil { state.sendError = nil }
        guard let data, state.editingMessageID == nil else { return }
        let id = conversationID
        let text = draft
        Task { await data.messages.composerChanged(conversationId: id, text: text) }
    }

    func dismissSendError() { state.sendError = nil }

    func stageImage(_ image: StagedImage) {
        guard state.editingMessageID == nil else { return }
        state.stagedImage = image
    }

    func removeStagedImage() { state.stagedImage = nil }

    var canSend: Bool {
        guard state.canWrite == true, !state.isUploading else { return false }
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return state.editingMessageID != nil ? hasText : hasText || state.stagedImage != nil
    }

    /// Optimistic: the composer clears at once and the row shows Sending… (03 §11). Images
    /// upload first, with the composer disabled until the upload returns.
    func send() async {
        guard let data, state.canWrite == true, !state.isUploading else { return }
        if let editing = state.editingMessageID {
            await submitEdit(messageId: editing)
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let image = state.stagedImage
        guard !text.isEmpty || image != nil else { return }
        draft = ""
        state.stagedImage = nil
        state.sendError = nil
        var attachment: Attachment?
        if let image {
            state.isUploading = true
            defer { state.isUploading = false }
            do {
                attachment = try await data.attachments.upload(
                    data: image.data,
                    fileName: image.fileName ?? StagedImage.defaultFileName,
                    mimeType: image.mimeType
                )
            } catch {
                restoreAfterUploadFailure(text: text, image: image, error: error)
                return
            }
        }
        guard await data.messages.send(text: text, attachment: attachment, conversationId: conversationID) != nil
        else { return }
        scroll(to: .latest)
    }

    /// A draft typed during the upload is never overwritten (03 §11).
    private func restoreAfterUploadFailure(text: String, image: StagedImage, error: any Error) {
        if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { draft = text }
        state.stagedImage = image
        state.sendError = SendErrorKind(WaiveraError.from(error))
        platform.haptic(.sendFailed)
    }

    private func submitEdit(messageId: Int) async {
        guard let data else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await data.messages.edit(messageId: messageId, conversationId: conversationID, text: text)
            state.editingMessageID = nil
            draft = ""
        } catch {
            interactions.fail(.edit, error)
        }
    }

    func startEdit(_ message: ChatMessage) {
        interactions.closeFocus()
        interactions.dismissSheet()
        state.editingMessageID = message.id
        state.stagedImage = nil
        draft = message.copyableText
    }

    func cancelEdit() {
        state.editingMessageID = nil
        draft = ""
    }

    // MARK: Rows and actions

    func toggleTimestamp(_ key: String) {
        state.visibleTimestamps.formSymmetricDifference([key])
    }

    func openActions(_ message: ChatMessage) {
        guard ChatActions.canOpen(message) else { return }
        interactions.openActions(
            ChatActions.model(message, viewerId: context.viewerId, canWrite: state.canWrite, allowsReply: true)
        )
    }

    /// Reply from the focus overlay or the thread chip: replies live in the thread (04 §1).
    func openThread(_ message: ChatMessage) {
        interactions.closeFocus()
        interactions.dismissSheet()
        onOpenThread(message.threadRootId ?? message.id, nil)
    }

    func retry(clientMessageId: String) async {
        sendTracker.markRetried(clientMessageId)
        state.sendError = nil
        await interactions.retry(clientMessageId: clientMessageId)
    }

    func discard(clientMessageId: String) async {
        sendTracker.markDiscarded(clientMessageId)
        await interactions.discard(clientMessageId: clientMessageId)
    }

    /// A failed row's Edit puts its text back in the composer and drops the failed copy.
    func editFailed(_ outgoing: OutgoingMessage) async {
        draft = outgoing.text
        await discard(clientMessageId: outgoing.clientMessageId)
    }

    /// Sheets hold message ids; the screen looks the current copy up here.
    func message(_ messageId: Int) -> ChatMessage? {
        state.items.lazy.compactMap { $0.message(messageId) }.first
    }

    // MARK: Call (03 §19)

    /// Video calls run on the web; the header button and the banner both hand off.
    func openCall() async {
        guard let data, let conversation = context.conversation, !state.call.isOpening else { return }
        state.call.isOpening = true
        defer { state.call.isOpening = false }
        do {
            let url = try await data.callURL(conversation)
            guard let safe = SafeLinks.url(url.absoluteString) else {
                interactions.fail(.call, nil)
                return
            }
            platform.openExternally(safe)
        } catch {
            interactions.fail(.call, error)
        }
    }
}
