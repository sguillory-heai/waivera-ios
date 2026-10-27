import Foundation
import WaiveraAPI
import WaiveraRealtime

extension ChatEngine: MessagesRepository {
    public nonisolated func timeline(conversationId: Int) -> AsyncStream<Resource<MessageTimeline>> {
        timelineCells.cell(conversationId).stream()
    }

    public func open(conversationId: Int) async {
        openConversations[conversationId, default: 0] += 1
        presence.setVisible(conversationId, true)
        await realtime.join(conversationId: conversationId)
        if timelines[conversationId]?.isLoaded != true, timelines[conversationId]?.messages.isEmpty ?? true {
            await showCachedPage(conversationId)
        }
        await refresh(conversationId: conversationId)
    }

    public func close(conversationId: Int) async {
        guard let count = openConversations[conversationId] else { return }
        openConversations[conversationId] = count > 1 ? count - 1 : nil
        presence.setVisible(conversationId, false)
        await realtime.leave(conversationId: conversationId)
        await throttle.stop(conversationId: conversationId)
    }

    /// The cached newest page renders while the network request runs.
    private func showCachedPage(_ conversationId: Int) async {
        guard let viewer, let cached = await store.load([ChatMessage].self, for: .messages(conversationId)),
            self.viewer == viewer
        else { return }
        var state = timelines[conversationId] ?? TimelineState()
        for message in cached where state.messages[message.id] == nil { state.messages[message.id] = message }
        state.phase = .loading
        timelines[conversationId] = state
        publishTimeline(conversationId)
    }

    /// Fetches the newest page and merges it by id. Used on open, pull-to-refresh and after
    /// every reconnect (05 §2).
    public func refresh(conversationId: Int) async {
        guard let mapper else { return }
        let current = generation
        timelines[conversationId, default: TimelineState()].phase = .loading
        publishTimeline(conversationId)
        do {
            let page = try await api.messagesPage(conversationId: conversationId)
            guard generation == current else { return }
            applyNewestPage(
                page.compactMap { mapper.message($0, conversationId: conversationId) },
                to: conversationId,
                rawCount: page.count
            )
        } catch {
            guard generation == current else { return }
            timelines[conversationId, default: TimelineState()].phase = .failed(WaiveraError.from(error))
            publishTimeline(conversationId)
        }
    }

    func applyNewestPage(_ messages: [ChatMessage], to conversationId: Int, rawCount: Int) {
        var state = timelines[conversationId] ?? TimelineState()
        let roots = messages.filter { !$0.isThreadReply }
        let overlaps = roots.contains { state.messages[$0.id] != nil }
        if state.isLoaded, !overlaps, rawCount >= APIClient.messagePageSize {
            // More than a page arrived while away: restart from this page rather than leave a gap.
            state.messages.removeAll()
            state.hasOlder = true
        } else if !state.isLoaded {
            state.hasOlder = rawCount >= APIClient.messagePageSize
        }
        for message in roots { state.messages[message.id] = state.messages[message.id]?.merging(message) ?? message }
        if !state.isLoaded {
            for message in state.buffered where !message.isThreadReply {
                state.messages[message.id] = state.messages[message.id]?.merging(message) ?? message
            }
            state.buffered.removeAll()
        }
        state.isLoaded = true
        state.phase = .loaded
        state.updatedAt = clock.now
        timelines[conversationId] = state
        for message in messages where message.isThreadReply { storeThreadReply(message, countIfNew: false) }
        for message in messages { reconcilePending(with: message) }
        publishTimeline(conversationId)
        persistTimeline(conversationId)
    }

    /// Older history. Stops when a page is short or the cursor stops moving (gap G-06).
    public func loadOlder(conversationId: Int) async {
        guard let mapper, var state = timelines[conversationId], state.isLoaded, state.hasOlder,
            !state.isLoadingOlder, let oldest = state.messages.keys.min()
        else { return }
        let current = generation
        state.isLoadingOlder = true
        timelines[conversationId] = state
        publishTimeline(conversationId)
        do {
            let page = try await api.messagesPage(conversationId: conversationId, beforeMessageId: oldest)
            guard generation == current, var state = timelines[conversationId] else { return }
            let messages = page.compactMap { mapper.message($0, conversationId: conversationId) }
            let newOldest = messages.map(\.id).min()
            state.hasOlder = page.count >= APIClient.messagePageSize && (newOldest.map { $0 < oldest } ?? false)
            for message in messages where !message.isThreadReply {
                state.messages[message.id] = state.messages[message.id]?.merging(message) ?? message
            }
            state.isLoadingOlder = false
            state.olderPageError = nil
            timelines[conversationId] = state
            for message in messages where message.isThreadReply { storeThreadReply(message, countIfNew: false) }
        } catch {
            guard generation == current else { return }
            // Reported on its own: the rows on screen are not stale because one older page failed.
            timelines[conversationId]?.isLoadingOlder = false
            timelines[conversationId]?.olderPageError = WaiveraError.from(error)
        }
        publishTimeline(conversationId)
    }

    /// Brings `messageId` into the timeline for a deep link, push or bookmark (03 §9) through the
    /// message-context endpoint. The window is merged only once it joins the loaded history:
    /// newer messages are fetched forward from the window until they reach the loaded rows or the
    /// end of the conversation, so scrolling from the target to the newest message never crosses
    /// a hole (AF-03). Returns whether the target is in the timeline afterwards.
    @discardableResult
    public func loadAround(conversationId: Int, messageId: Int) async throws -> Bool {
        guard let mapper else { throw WaiveraError.signedOut }
        guard let loaded = timelines[conversationId], loaded.isLoaded else { return false }
        if loaded.messages[messageId] != nil { return true }
        let current = generation
        let window: [ChatMessage]?
        do {
            window = try await contextWindow(conversationId: conversationId, messageId: messageId, mapper: mapper)
        } catch {
            throw WaiveraError.from(error)
        }
        guard generation == current, let window, var state = timelines[conversationId] else { return false }
        let oldestBefore = state.messages.keys.min()
        for message in window where !message.isThreadReply {
            state.messages[message.id] = state.messages[message.id]?.merging(message) ?? message
        }
        if let oldestBefore, let newOldest = state.messages.keys.min(), newOldest < oldestBefore {
            state.hasOlder = window.filter { $0.id < messageId }.count >= Self.contextBefore
        }
        timelines[conversationId] = state
        for message in window where message.isThreadReply { storeThreadReply(message, countIfNew: false) }
        publishTimeline(conversationId)
        return state.messages[messageId] != nil
    }

    /// The context window plus forward pages until it joins the loaded rows or reaches the
    /// newest message; `nil` when the target is gone or the gap is too long to close.
    private func contextWindow(conversationId: Int, messageId: Int, mapper: ChatMapper) async throws
        -> [ChatMessage]?
    {
        let page = try await api.messageContext(
            conversationId: conversationId,
            messageId: messageId,
            before: Self.contextBefore,
            after: Self.contextAfter
        )
        var messages = page.compactMap { mapper.message($0, conversationId: conversationId) }
        guard messages.contains(where: { $0.id == messageId }) else { return nil }
        var reachedEnd = messages.filter { $0.id > messageId }.count < Self.contextAfter
        for _ in 0..<Self.maxForwardPages {
            guard let newest = messages.map(\.id).max() else { return nil }
            if reachedEnd || Self.joins(newest, loaded: timelines[conversationId]) { return messages }
            let next = try await api.messageContext(
                conversationId: conversationId,
                messageId: newest,
                before: 0,
                after: Self.contextAfter
            )
            let newer = next.compactMap { mapper.message($0, conversationId: conversationId) }.filter { $0.id > newest }
            messages += newer
            reachedEnd = newer.count < Self.contextAfter
        }
        guard let newest = messages.map(\.id).max() else { return nil }
        return reachedEnd || Self.joins(newest, loaded: timelines[conversationId]) ? messages : nil
    }

    /// Whether a window ending at `newest` touches the loaded rows (by id, which rises with time).
    static func joins(_ newest: Int, loaded state: TimelineState?) -> Bool {
        guard let oldest = state?.messages.keys.min() else { return true }
        return newest >= oldest
    }

    @discardableResult
    public func send(text: String, attachment: Attachment?, conversationId: Int) async -> OutgoingMessage? {
        await throttle.stop(conversationId: conversationId)
        return enqueue(text: text, attachment: attachment, conversationId: conversationId, parentMessageId: nil)
    }

    public func composerChanged(conversationId: Int, text: String) async {
        guard realtime.currentStatus.isConnected else { return }
        await throttle.textChanged(conversationId: conversationId, text: text)
    }

    /// `MarkAsRead` over the hub (REST when disconnected), then read-through of the newest root
    /// message, once per message id (03 §12).
    public func markRead(conversationId: Int) async throws {
        let previous = conversationsById[conversationId].map { (unread: $0.unreadCount, readAt: $0.lastReadAt) }
        clearUnread(conversationId)
        do {
            try await sendMarkAsRead(conversationId)
        } catch {
            // Restore only if nothing newer changed the row meanwhile (AF-08).
            if let previous, previous.unread > 0, var row = conversationsById[conversationId], row.unreadCount == 0 {
                row.unreadCount = previous.unread
                row.lastReadAt = previous.readAt
                conversationsById[conversationId] = row
                publishConversations()
                persistConversations()
            }
            throw WaiveraError.from(error)
        }
        guard
            let newest = timelines[conversationId].flatMap({ state in
                state.messages.values.filter { !$0.isThreadReply }.map(\.id).max()
            })
        else { return }
        await readThrough(conversationId: conversationId, messageId: newest, threadRootMessageId: nil)
    }

    func sendMarkAsRead(_ conversationId: Int) async throws {
        if realtime.currentStatus.isConnected, (try? await realtime.markAsRead(conversationId: conversationId)) != nil {
            return
        }
        try await api.markAsRead(conversationId: conversationId)
    }

    func readThrough(conversationId: Int, messageId: Int, threadRootMessageId: Int?) async {
        let key = "\(conversationId):\(threadRootMessageId.map(String.init) ?? "root")"
        guard lastReadThrough[key] != messageId else { return }
        lastReadThrough[key] = messageId
        do {
            let state = try await api.readThrough(
                conversationId: conversationId,
                ChatReadThroughRequest(lastVisibleMessageId: messageId, threadRootMessageId: threadRootMessageId)
            )
            readStateBroadcaster.send(state)
        } catch {
            // Released so the next change retries.
            if lastReadThrough[key] == messageId { lastReadThrough[key] = nil }
        }
    }

    // MARK: MessageActions

    public func edit(messageId: Int, conversationId: Int, text: String) async throws {
        guard let mapper else { throw WaiveraError.signedOut }
        guard let outgoing = RichText.outgoingDocument(for: text) else { throw WaiveraError.invalidRequest }
        let response = try await api.editMessage(
            messageId: messageId,
            EditMessageRequest(newContent: outgoing.text, doc: outgoing.doc)
        )
        guard let message = mapper.message(response, conversationId: conversationId) else { return }
        upsert(message, fromRealtime: false)
        // The inbox preview shows the edit at once, not only when the hub echoes it (AF-10).
        if var row = conversationsById[conversationId], let last = row.lastMessage, last.id == message.id {
            row.lastMessage = last.merging(message)
            conversationsById[conversationId] = row
            publishConversations()
            persistConversations()
        }
    }

    public func delete(messageId: Int, conversationId: Int) async throws {
        _ = try await api.deleteMessage(messageId: messageId)
        updateMessage(messageId, conversationId: conversationId) {
            ChatMapper.applying(MessageDeleteEvent(messageId: messageId, conversationId: conversationId), to: $0)
        }
    }

    /// One reaction per user per message: the same emoji removes it, another replaces it.
    public func toggleReaction(_ emoji: String, messageId: Int, conversationId: Int) async throws {
        guard let viewer else { throw WaiveraError.signedOut }
        guard realtime.currentStatus.isConnected else { throw WaiveraError.realtimeUnavailable }
        guard let original = message(messageId, conversationId: conversationId) else { throw WaiveraError.notFound }
        let removing = original.reactions.contains { $0.userId == viewer.id && $0.emoji == emoji }
        let event = ReactionEvent(
            conversationId: conversationId,
            messageId: messageId,
            userId: viewer.id,
            reactionType: removing ? nil : emoji,
            action: removing ? .removed : .added
        )
        updateMessage(messageId, conversationId: conversationId) { ChatMapper.applying(event, to: $0) }
        do {
            try await realtime.sendReaction(messageId: messageId, reactionType: emoji)
        } catch {
            updateMessage(messageId, conversationId: conversationId) { _ in original }
            throw WaiveraError.from(error)
        }
    }

    // MARK: Cache writes

    func message(_ messageId: Int, conversationId: Int) -> ChatMessage? {
        if let message = timelines[conversationId]?.messages[messageId] { return message }
        for thread in threads.values where thread.conversationId == conversationId {
            if thread.root?.id == messageId { return thread.root }
            if let reply = thread.replies[messageId] { return reply }
        }
        return nil
    }

    /// Applies `transform` wherever the message is cached: timeline, thread roots and replies.
    func updateMessage(_ messageId: Int, conversationId: Int, _ transform: (ChatMessage) -> ChatMessage) {
        if let message = timelines[conversationId]?.messages[messageId] {
            timelines[conversationId]?.messages[messageId] = transform(message)
            publishTimeline(conversationId)
            persistTimeline(conversationId)
        }
        for (rootId, thread) in threads where thread.conversationId == conversationId {
            var changed = thread
            if let root = thread.root, root.id == messageId { changed.root = transform(root) }
            if let reply = thread.replies[messageId] { changed.replies[messageId] = transform(reply) }
            if changed.root != thread.root || changed.replies != thread.replies {
                threads[rootId] = changed
                publishThread(rootId)
            }
        }
        if var row = conversationsById[conversationId], let last = row.lastMessage, last.id == messageId {
            row.lastMessage = transform(last)
            conversationsById[conversationId] = row
            publishConversations()
        }
    }

    /// Inserts or merges a server message into its timeline or thread.
    func upsert(_ message: ChatMessage, fromRealtime: Bool) {
        if message.isThreadReply {
            storeThreadReply(message, countIfNew: true)
            return
        }
        let conversationId = message.conversationId
        var state = timelines[conversationId] ?? TimelineState()
        if !state.isLoaded, fromRealtime, openConversations[conversationId] == nil, state.messages.isEmpty {
            // Nobody is looking and nothing is loaded: the next open fetches it.
            return
        }
        if !state.isLoaded, state.phase == .loading, fromRealtime {
            state.buffered.append(message)
        } else {
            state.messages[message.id] = state.messages[message.id]?.merging(message) ?? message
        }
        timelines[conversationId] = state
        if let thread = threads[message.id] {
            threads[message.id]?.root = thread.root?.merging(message) ?? message
            publishThread(message.id)
        }
        publishTimeline(conversationId)
        persistTimeline(conversationId)
    }
}
