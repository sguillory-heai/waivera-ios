import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraRealtime

extension FakeChatRepository: MessagesRepository {
    public nonisolated func timeline(conversationId: Int) -> AsyncStream<Resource<MessageTimeline>> {
        timelineCells.cell(conversationId).stream()
    }

    public func open(conversationId: Int) async {
        calls.record("open:\(conversationId)")
        presence.setVisible(conversationId, true)
        await refresh(conversationId: conversationId)
    }

    public func close(conversationId: Int) async {
        calls.record("close:\(conversationId)")
        presence.setVisible(conversationId, false)
    }

    public func refresh(conversationId: Int) async {
        publishTimeline(conversationId, phase: .loading)
        let controls = timelineControls.get()
        if controls.latency > .zero { try? await clock.sleep(for: controls.latency) }
        if let failure = controls.failure {
            publishTimeline(conversationId, phase: .failed(failure))
            return
        }
        loadedTimelines.insert(conversationId)
        publishTimeline(conversationId, phase: .loaded)
    }

    public func loadOlder(conversationId: Int) async {
        calls.record("loadOlder:\(conversationId)")
        if olderPageFailure != nil {
            olderPageFailed.insert(conversationId)
        } else {
            olderPageFailed.remove(conversationId)
        }
        publishTimeline(conversationId)
    }

    /// Every demo message is already loaded, so the target is either there or unknown.
    @discardableResult
    public func loadAround(conversationId: Int, messageId: Int) async throws -> Bool {
        calls.record("loadAround:\(conversationId):\(messageId)")
        if let failure = timelineControls.get().failure { throw failure }
        return messages[conversationId]?.contains { $0.id == messageId } ?? false
    }

    @discardableResult
    public func send(text: String, attachment: Attachment?, conversationId: Int) async -> OutgoingMessage? {
        enqueue(text: text, attachment: attachment, conversationId: conversationId, parentMessageId: nil)
    }

    /// Optimistic like the live engine: clears at once, restores and throws when
    /// `setMarkReadFailure` is set.
    public func markRead(conversationId: Int) async throws {
        calls.record("markRead:\(conversationId)")
        let previous = inbox.value?.first { $0.id == conversationId }?.unreadCount ?? 0
        updateConversation(conversationId) { $0.unreadCount = 0 }
        if let markReadFailure {
            updateConversation(conversationId) { $0.unreadCount = previous }
            throw markReadFailure
        }
    }

    public func composerChanged(conversationId: Int, text: String) async {
        calls.record("typing:\(conversationId)")
    }

    // MARK: MessageActions

    public func retry(clientMessageId: String) async {
        calls.record("retry:\(clientMessageId)")
        guard var entry = pending[clientMessageId] else { return }
        entry.state = .sending
        entry.attempts += 1
        pending[clientMessageId] = entry
        resolve(entry)
    }

    public func discard(clientMessageId: String) async {
        calls.record("discard:\(clientMessageId)")
        guard let entry = pending.removeValue(forKey: clientMessageId) else { return }
        publish(entry)
    }

    public func edit(messageId: Int, conversationId: Int, text: String) async throws {
        calls.record("edit:\(messageId)")
        updateMessage(messageId, conversationId: conversationId) { message in
            message.content = text
            message.plaintext = text
            message.doc = nil
            message.isEdited = true
            message.editedAt = clock.now
        }
    }

    public func delete(messageId: Int, conversationId: Int) async throws {
        calls.record("delete:\(messageId)")
        updateMessage(messageId, conversationId: conversationId) { message in
            message = ChatMapper.applying(
                MessageDeleteEvent(messageId: messageId, conversationId: conversationId),
                to: message
            )
        }
    }

    public func toggleReaction(_ emoji: String, messageId: Int, conversationId: Int) async throws {
        calls.record("react:\(messageId):\(emoji)")
        guard reactionsAvailable else { throw WaiveraError.realtimeUnavailable }
        let viewerId = viewer.id
        updateMessage(messageId, conversationId: conversationId) { message in
            let removing = message.reactions.contains { $0.userId == viewerId && $0.emoji == emoji }
            let event = ReactionEvent(
                conversationId: conversationId,
                messageId: messageId,
                userId: viewerId,
                reactionType: removing ? nil : emoji,
                action: removing ? .removed : .added
            )
            message = ChatMapper.applying(event, to: message)
        }
    }

    // MARK: Outbox

    func enqueue(text: String, attachment: Attachment?, conversationId: Int, parentMessageId: Int?)
        -> OutgoingMessage?
    {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || attachment != nil else { return nil }
        nextClientId += 1
        let entry = OutgoingMessage(
            clientMessageId: "fake-client-\(nextClientId)",
            conversationId: conversationId,
            parentMessageId: parentMessageId,
            text: trimmed,
            doc: nil,
            attachment: attachment,
            createdAt: clock.now,
            authorId: viewer.id
        )
        pending[entry.clientMessageId] = entry
        calls.record("send:\(conversationId)")
        resolve(entry)
        return entry
    }

    private func resolve(_ entry: OutgoingMessage) {
        switch sendOutcome {
        case .deliver:
            confirm(entry)
        case .fail(let failure):
            var failed = entry
            failed.state = .failed(failure)
            pending[entry.clientMessageId] = failed
            publish(failed)
        case .hold:
            publish(entry)
        }
    }

    func confirm(_ entry: OutgoingMessage) {
        pending[entry.clientMessageId] = nil
        nextMessageId += 1
        var message = ChatMessage(
            id: nextMessageId,
            conversationId: entry.conversationId,
            isMine: true,
            createdAt: clock.now
        )
        message.clientMessageId = entry.clientMessageId
        message.author = viewer.asChatUser
        message.authorId = viewer.id
        message.content = entry.text
        message.plaintext = entry.text
        message.attachment = entry.attachment
        message.parentMessageId = entry.parentMessageId
        message.threadRootMessageId = entry.parentMessageId
        if let rootId = entry.parentMessageId {
            storeReply(message, rootId: rootId)
        } else {
            messages[entry.conversationId, default: []].append(message)
            updateConversation(entry.conversationId) { $0.lastMessage = message }
        }
        publish(entry)
    }

    private func publish(_ entry: OutgoingMessage) {
        if let rootId = entry.parentMessageId {
            publishThread(rootId)
        } else {
            publishTimeline(entry.conversationId)
        }
    }
}

extension FakeChatRepository: ThreadsRepository {
    public nonisolated func thread(rootMessageId: Int, conversationId: Int) -> AsyncStream<Resource<ThreadTimeline>> {
        threadCells.cell(rootMessageId).stream()
    }

    public func open(rootMessageId: Int, conversationId: Int) async {
        calls.record("openThread:\(rootMessageId)")
        presence.setVisible(conversationId, true)
        await refresh(rootMessageId: rootMessageId, conversationId: conversationId)
    }

    public func close(rootMessageId: Int, conversationId: Int) async {
        calls.record("closeThread:\(rootMessageId)")
        presence.setVisible(conversationId, false)
    }

    public func refresh(rootMessageId: Int, conversationId: Int) async {
        if threadsById[rootMessageId] == nil {
            threadsById[rootMessageId] = ThreadTimeline(
                rootMessageId: rootMessageId,
                conversationId: conversationId,
                root: messages[conversationId]?.first { $0.id == rootMessageId }
            )
        }
        publishThread(rootMessageId, phase: .loading)
        let controls = timelineControls.get()
        if controls.latency > .zero { try? await clock.sleep(for: controls.latency) }
        if let failure = controls.failure {
            publishThread(rootMessageId, phase: .failed(failure))
            return
        }
        loadedThreads.insert(rootMessageId)
        publishThread(rootMessageId, phase: .loaded)
    }

    @discardableResult
    public func reply(text: String, attachment: Attachment?, rootMessageId: Int, conversationId: Int) async
        -> OutgoingMessage?
    {
        calls.record("reply:\(rootMessageId)")
        if threadsById[rootMessageId] == nil {
            threadsById[rootMessageId] = ThreadTimeline(rootMessageId: rootMessageId, conversationId: conversationId)
        }
        return enqueue(
            text: text,
            attachment: attachment,
            conversationId: conversationId,
            parentMessageId: rootMessageId
        )
    }

    public func markRead(rootMessageId: Int, conversationId: Int) async {
        calls.record("markThreadRead:\(rootMessageId)")
    }
}
