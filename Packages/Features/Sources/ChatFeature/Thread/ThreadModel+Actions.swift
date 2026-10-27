import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// The reply composer and the row actions.
extension ThreadModel {
    // MARK: Composer

    /// Threads send no typing events (04 §1); editing only clears the error banner.
    func draftChanged() {
        if state.sendError != nil { state.sendError = nil }
    }

    func dismissSendError() { state.sendError = nil }

    var canSend: Bool {
        state.canWrite == true && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func send() async {
        guard let data, let conversationId = conversationID, state.canWrite == true else { return }
        if let editing = state.editingMessageID {
            await submitEdit(messageId: editing, conversationId: conversationId)
            return
        }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        state.sendError = nil
        let sent = await data.threads.reply(
            text: text,
            attachment: nil,
            rootMessageId: rootMessageID,
            conversationId: conversationId
        )
        guard sent != nil else {
            // Rejected before it reached the outbox: the exact draft comes back (04 §3).
            if draft.isEmpty { draft = text }
            return
        }
        platform.haptic(.messageSent)
        nextScrollId += 1
        state.scrollCommand = ScrollCommand(id: nextScrollId, target: .latest)
    }

    private func submitEdit(messageId: Int, conversationId: Int) async {
        guard let data else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        do {
            try await data.threads.edit(messageId: messageId, conversationId: conversationId, text: text)
            state.editingMessageID = nil
            draft = ""
            platform.haptic(.success)
        } catch {
            interactions.fail(.edit, error)
        }
    }

    func startEdit(_ message: ChatMessage) {
        interactions.dismissSheet()
        state.editingMessageID = message.id
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

    /// Reply here focuses the reply box; it never opens a nested thread.
    func openActions(_ message: ChatMessage) {
        guard ChatActions.canOpen(message) else { return }
        var model = ChatActions.model(message, viewerId: context.viewerId, canWrite: state.canWrite, allowsReply: false)
        model.canReply = state.canWrite == true
        interactions.openActions(model)
    }

    func replyFromSheet() {
        interactions.dismissSheet()
        state.focusRequest += 1
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

    func editFailed(_ outgoing: OutgoingMessage) async {
        draft = outgoing.text
        await discard(clientMessageId: outgoing.clientMessageId)
    }

    func message(_ messageId: Int) -> ChatMessage? {
        allMessages.first { $0.id == messageId } ?? state.root.flatMap { $0.message.id == messageId ? $0.message : nil }
    }
}
