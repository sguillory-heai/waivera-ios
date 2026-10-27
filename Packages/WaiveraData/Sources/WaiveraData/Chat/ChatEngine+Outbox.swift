import Foundation
import WaiveraAPI
import WaiveraRealtime

/// Optimistic sends (03 §11): client-generated id, hub first with REST fallback, automatic
/// retry for transient failures, then Retry/Discard. The client id is the server's
/// idempotency key, so a retry never duplicates a message that did reach the server.
extension ChatEngine {
    func enqueue(text: String, attachment: Attachment?, conversationId: Int, parentMessageId: Int?)
        -> OutgoingMessage?
    {
        guard viewer != nil else { return nil }
        let outgoing = RichText.outgoingDocument(for: text)
        guard outgoing != nil || attachment != nil else { return nil }
        let entry = OutgoingMessage(
            clientMessageId: UUID().uuidString.lowercased(),
            conversationId: conversationId,
            parentMessageId: parentMessageId,
            text: outgoing?.text ?? "",
            doc: outgoing?.doc,
            attachment: attachment,
            createdAt: clock.now
        )
        outbox[entry.clientMessageId] = entry
        publishPending(entry)
        persistOutbox()
        startAttempt(entry.clientMessageId)
        return entry
    }

    public func retry(clientMessageId: String) async {
        guard var entry = outbox[clientMessageId] else { return }
        if entry.state == .sending, outboxTasks[clientMessageId] != nil { return }
        outboxTasks.removeValue(forKey: clientMessageId)?.cancel()
        entry.attempts = 0
        entry.state = .sending
        outbox[clientMessageId] = entry
        publishPending(entry)
        startAttempt(clientMessageId)
    }

    public func discard(clientMessageId: String) async {
        outboxTasks.removeValue(forKey: clientMessageId)?.cancel()
        guard let entry = outbox.removeValue(forKey: clientMessageId) else { return }
        publishPending(entry)
        persistOutbox()
    }

    /// Restarts queued sends after sign-in, a reconnect or the network returning.
    public func resumeOutbox() {
        for entry in outbox.values where !entry.isFailed && outboxTasks[entry.clientMessageId] == nil {
            startAttempt(entry.clientMessageId)
        }
    }

    func startAttempt(_ clientMessageId: String, after delay: Duration = .zero) {
        let clock = clock
        outboxTasks[clientMessageId] = Task {
            if delay > .zero { try? await clock.sleep(for: delay) }
            guard !Task.isCancelled else { return }
            await self.attempt(clientMessageId)
        }
    }

    func attempt(_ clientMessageId: String) async {
        guard var entry = outbox[clientMessageId], let mapper else { return }
        let current = generation
        entry.state = .sending
        entry.attempts += 1
        outbox[clientMessageId] = entry
        publishPending(entry)
        do {
            let response = try await transport(entry)
            guard generation == current else { return }
            outboxTasks[clientMessageId] = nil
            guard var message = mapper.message(response, conversationId: entry.conversationId) else {
                throw WaiveraError.invalidResponse
            }
            message.isMine = true
            message.clientMessageId = message.clientMessageId ?? clientMessageId
            confirm(entry, with: message)
        } catch {
            guard generation == current, var entry = outbox[clientMessageId] else { return }
            outboxTasks[clientMessageId] = nil
            let failure = WaiveraError.from(error)
            if failure.isTransient, entry.attempts < Self.maxAutomaticAttempts {
                entry.state = .queued(attempt: entry.attempts)
                outbox[clientMessageId] = entry
                startAttempt(clientMessageId, after: .seconds(1 << (entry.attempts - 1)))
            } else {
                entry.state = .failed(failure)
                outbox[clientMessageId] = entry
            }
            publishPending(entry)
            persistOutbox()
        }
    }

    /// The hub is the preferred path; REST is the fallback when it is down (hub.md).
    private func transport(_ entry: OutgoingMessage) async throws -> MessageSendResponse {
        if realtime.currentStatus.isConnected {
            do {
                return try await realtime.sendMessage(
                    HubSendMessage(
                        conversationId: entry.conversationId,
                        text: entry.text,
                        doc: entry.doc,
                        parentMessageId: entry.parentMessageId,
                        clientMessageId: entry.clientMessageId,
                        attachmentUrl: entry.attachment?.url
                    )
                )
            } catch let error as WaiveraError where error == .realtimeUnavailable {
                // Dropped between the check and the call: fall through to REST.
            }
        }
        return try await api.sendMessage(
            SendMessageRequest(
                conversationId: entry.conversationId,
                clientMessageId: entry.clientMessageId,
                text: entry.text,
                doc: entry.doc,
                attachmentUrl: entry.attachment?.url,
                parentMessageId: entry.parentMessageId
            )
        )
    }

    private func confirm(_ entry: OutgoingMessage, with message: ChatMessage) {
        outbox[entry.clientMessageId] = nil
        upsert(message, fromRealtime: false)
        if !message.isThreadReply { applyToPreview(message, incrementUnread: false) }
        publishPending(entry)
        persistOutbox()
    }

    /// Drops the pending row a server message confirms: by client id when echoed, else by
    /// author, conversation, thread, text and a 60 s window (PLAN parity fix).
    func reconcilePending(with message: ChatMessage) {
        guard message.isMine, !outbox.isEmpty else { return }
        if let clientId = message.clientMessageId, let entry = outbox[clientId] {
            removePending(entry)
            return
        }
        let text = message.bodyText?.trimmed ?? ""
        guard !text.isEmpty else { return }
        let match = outbox.values
            .filter { entry in
                entry.conversationId == message.conversationId && entry.parentMessageId == message.threadRootId
                    && entry.text.trimmed == text
                    && abs((message.createdAt ?? clock.now).timeIntervalSince(entry.createdAt)) < Self.reconcileWindow
            }
            .min { $0.createdAt < $1.createdAt }
        if let match { removePending(match) }
    }

    private func removePending(_ entry: OutgoingMessage) {
        outboxTasks.removeValue(forKey: entry.clientMessageId)?.cancel()
        outbox[entry.clientMessageId] = nil
        publishPending(entry)
        persistOutbox()
    }

    func publishPending(_ entry: OutgoingMessage) {
        if let root = entry.parentMessageId {
            if threads[root] == nil { threads[root] = ThreadState(conversationId: entry.conversationId) }
            publishThread(root)
        } else {
            publishTimeline(entry.conversationId)
        }
    }

    /// The pending sends for a conversation, failed ones included (Retry in both places).
    public func pendingMessages(conversationId: Int) -> [OutgoingMessage] {
        outbox.values.filter { $0.conversationId == conversationId }.sorted { $0.createdAt < $1.createdAt }
    }
}
