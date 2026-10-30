import Foundation
import WaiveraAPI
import WaiveraRealtime

/// Optimistic sends (03 §11): client-generated id, hub first with REST fallback, automatic
/// retry for transient failures, then Retry/Discard. The client id is the server's
/// idempotency key, so a retry never duplicates a message that did reach the server.
extension ChatEngine {
    /// Longest wait between tries while the device is offline (IF-04).
    static let maxOfflineBackoff: Duration = .seconds(60)

    func enqueue(
        text: String,
        attachment: Attachment?,
        conversationId: Int,
        parentMessageId: Int?
    ) async -> OutgoingMessage? {
        guard let viewer else { return nil }
        let outgoing = RichText.outgoingDocument(for: text)
        guard outgoing != nil || attachment != nil else { return nil }
        let entry = OutgoingMessage(
            clientMessageId: UUID().uuidString.lowercased(),
            conversationId: conversationId,
            parentMessageId: parentMessageId,
            text: outgoing?.text ?? "",
            doc: outgoing?.doc,
            attachment: attachment,
            createdAt: clock.now,
            authorId: viewer.id
        )
        outbox[entry.clientMessageId] = entry
        publishPending(entry)
        // On disk before the first try, so a send the system suspends mid-flight is retried
        // after relaunch instead of vanishing (IF-03).
        persistOutbox()
        await flushPersistence()
        guard outbox[entry.clientMessageId] != nil else { return entry }
        startAttempt(entry.clientMessageId)
        return entry
    }

    public func sendAndWait(
        text: String,
        conversationId: Int,
        threadRootMessageId: Int?,
        timeout: Duration
    ) async -> OutboxOutcome {
        await throttle.stop(conversationId: conversationId)
        guard
            let entry = await enqueue(
                text: text,
                attachment: nil,
                conversationId: conversationId,
                parentMessageId: threadRootMessageId
            )
        else { return .dropped }
        return await outcome(of: entry.clientMessageId, timeout: timeout)
    }

    /// Waits until the entry is confirmed or needs the user, or until `timeout`.
    func outcome(of clientMessageId: String, timeout: Duration) async -> OutboxOutcome {
        if let settled = settledOutcome(clientMessageId) { return settled }
        let clock = clock
        let waiterId = UUID()
        return await withTaskGroup(of: OutboxOutcome.self) { group in
            group.addTask {
                await withTaskCancellationHandler {
                    await withCheckedContinuation { continuation in
                        Task { await self.addWaiter(waiterId, for: clientMessageId, continuation) }
                    }
                } onCancel: {
                    Task { await self.resolveWaiter(waiterId, with: .queued) }
                }
            }
            group.addTask {
                try? await clock.sleep(for: timeout)
                return .queued
            }
            let first = await group.next() ?? .queued
            group.cancelAll()
            return first
        }
    }

    private func settledOutcome(_ clientMessageId: String) -> OutboxOutcome? {
        guard let entry = outbox[clientMessageId] else {
            return confirmedClientIds.contains(clientMessageId) ? .sent : .dropped
        }
        if case .failed(let error) = entry.state { return .failed(error) }
        return nil
    }

    private func addWaiter(
        _ waiterId: UUID,
        for clientMessageId: String,
        _ continuation: CheckedContinuation<OutboxOutcome, Never>
    ) {
        if cancelledWaiters.remove(waiterId) != nil {
            continuation.resume(returning: .queued)
            return
        }
        if let settled = settledOutcome(clientMessageId) {
            continuation.resume(returning: settled)
            return
        }
        outboxWaiters[clientMessageId, default: [:]][waiterId] = continuation
    }

    private func resolveWaiter(_ waiterId: UUID, with outcome: OutboxOutcome) {
        for (clientMessageId, waiters) in outboxWaiters {
            guard let continuation = waiters[waiterId] else { continue }
            outboxWaiters[clientMessageId]?[waiterId] = nil
            continuation.resume(returning: outcome)
            return
        }
        cancelledWaiters.insert(waiterId)
    }

    /// Wakes everyone waiting on this entry.
    func settle(_ clientMessageId: String, _ outcome: OutboxOutcome) {
        if outcome == .sent { confirmedClientIds.insert(clientMessageId) }
        guard let waiters = outboxWaiters.removeValue(forKey: clientMessageId) else { return }
        for continuation in waiters.values { continuation.resume(returning: outcome) }
    }

    /// Sign-out: nobody waits on a queue that is being dropped.
    func settleAllWaiters() {
        let all = outboxWaiters
        outboxWaiters.removeAll()
        confirmedClientIds.removeAll()
        for waiters in all.values {
            for continuation in waiters.values { continuation.resume(returning: .dropped) }
        }
    }

    public func retry(clientMessageId: String) async {
        guard var entry = outbox[clientMessageId] else { return }
        if entry.state == .sending, outboxTasks[clientMessageId] != nil { return }
        outboxTasks.removeValue(forKey: clientMessageId)?.cancel()
        entry.attempts = 0
        offlineTries[clientMessageId] = nil
        entry.state = .sending
        outbox[clientMessageId] = entry
        publishPending(entry)
        startAttempt(clientMessageId)
    }

    public func discard(clientMessageId: String) async {
        outboxTasks.removeValue(forKey: clientMessageId)?.cancel()
        offlineTries[clientMessageId] = nil
        guard let entry = outbox.removeValue(forKey: clientMessageId) else { return }
        publishPending(entry)
        persistOutbox()
        settle(clientMessageId, .dropped)
    }

    /// Restarts queued sends after sign-in, a reconnect, the network returning or the app
    /// coming to the foreground (IF-04): a send waiting out an offline backoff goes now, and one
    /// that failed for a reason that can pass by itself (offline, a 5xx, a rate limit) starts a
    /// fresh automatic budget. Its Retry stays on screen until then. Sends that failed for a
    /// reason the user must fix are left for Retry.
    public func resumeOutbox() {
        for (clientMessageId, entry) in outbox {
            switch entry.state {
            case .sending:
                guard outboxTasks[clientMessageId] == nil else { continue }
            case .queued:
                outboxTasks.removeValue(forKey: clientMessageId)?.cancel()
            case .failed(let error):
                guard error.isTransient, outboxTasks[clientMessageId] == nil else { continue }
                outbox[clientMessageId]?.attempts = 0
                offlineTries[clientMessageId] = nil
            }
            startAttempt(clientMessageId)
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

    /// No network: the send waits for it without spending its automatic budget.
    static func isWaitingForNetwork(_ error: WaiveraError) -> Bool {
        error == .offline
    }

    /// 1, 2, 4 … seconds, capped at `maxOfflineBackoff`.
    static func offlineBackoff(afterTries tries: Int) -> Duration {
        let seconds = 1 << min(max(tries - 1, 0), 6)
        return min(.seconds(seconds), maxOfflineBackoff)
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
            offlineTries[clientMessageId] = nil
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
            let onlineAttempts = entry.attempts - offlineTries[clientMessageId, default: 0]
            if Self.isWaitingForNetwork(failure) {
                // Offline is not a failure the user can act on: keep it queued and keep trying,
                // backing off, until the network or a reconnect resumes it (IF-04).
                let tries = offlineTries[clientMessageId, default: 0] + 1
                offlineTries[clientMessageId] = tries
                entry.state = .queued(attempt: entry.attempts)
                outbox[clientMessageId] = entry
                startAttempt(clientMessageId, after: Self.offlineBackoff(afterTries: tries))
            } else if failure.isTransient, onlineAttempts < Self.maxAutomaticAttempts {
                entry.state = .queued(attempt: entry.attempts)
                outbox[clientMessageId] = entry
                startAttempt(clientMessageId, after: .seconds(1 << (onlineAttempts - 1)))
            } else {
                entry.state = .failed(failure)
                outbox[clientMessageId] = entry
                offlineTries[clientMessageId] = nil
                settle(clientMessageId, .failed(failure))
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
        settle(entry.clientMessageId, .sent)
    }

    /// Drops the pending row a server message confirms: by client id when echoed, else by
    /// author, conversation, thread, text and a 60 s window (PLAN parity fix). The text match
    /// runs only for a message without a client id: one that has an id no longer queued was
    /// already confirmed (a second delivery of a send response, hub echo or refresh), and
    /// matching it by text would drop a different queued message with the same words (AF-02).
    func reconcilePending(with message: ChatMessage) {
        guard message.isMine, !outbox.isEmpty else { return }
        if let clientId = message.clientMessageId {
            if let entry = outbox[clientId] { removePending(entry) }
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
        offlineTries[entry.clientMessageId] = nil
        outbox[entry.clientMessageId] = nil
        publishPending(entry)
        persistOutbox()
        settle(entry.clientMessageId, .sent)
    }

    func publishPending(_ entry: OutgoingMessage) {
        if let root = entry.parentMessageId {
            if threads[root] == nil { threads[root] = ThreadState(conversationId: entry.conversationId) }
            publishThread(root)
        } else {
            publishTimeline(entry.conversationId)
        }
        publishFailedSends()
    }

    /// Every conversation with a failed send, a thread reply included, as the conversation's own
    /// "Not sent" rows show it. Sending and queued entries are still on their way, so they do
    /// not count (Android `observeFailedSends`). Published only when the set changes.
    func publishFailedSends() {
        let failed = Set(outbox.values.filter(\.isFailed).map(\.conversationId))
        if failed != failedSendsCell.current { failedSendsCell.set(failed) }
    }

    /// The pending sends for a conversation, failed ones included (Retry in both places).
    public func pendingMessages(conversationId: Int) -> [OutgoingMessage] {
        outbox.values.filter { $0.conversationId == conversationId }.sorted { $0.createdAt < $1.createdAt }
    }
}
