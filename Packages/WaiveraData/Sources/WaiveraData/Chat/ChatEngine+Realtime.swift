import Foundation
import WaiveraAPI
import WaiveraRealtime

/// Hub events applied to the chat cache (05 §5-6).
extension ChatEngine {
    public func handle(_ event: ChatHubEvent) async {
        guard let viewer else { return }
        switch event {
        case .message(let dto), .conversationListMessage(let dto):
            await ingest(dto)
        case .attention(let dto, let reason):
            alert(for: dto, reason: reason)
        case .typing(let typing):
            guard typing.userId != viewer.id else { return }
            await typingTracker.received(
                conversationId: typing.conversationId,
                userId: typing.userId,
                isTyping: typing.isTyping
            )
        case .reaction(let reaction):
            updateMessage(reaction.messageId, conversationId: reaction.conversationId) {
                ChatMapper.applying(reaction, to: $0)
            }
        case .messageUpdated(let update):
            updateMessage(update.messageId, conversationId: update.conversationId) {
                ChatMapper.applying(update, to: $0)
            }
        case .messageDeleted(let delete):
            updateMessage(delete.messageId, conversationId: delete.conversationId) {
                ChatMapper.applying(delete, to: $0)
            }
        case .bookmark(let update?):
            applyBookmark(messageId: update.messageId, isBookmarked: update.isBookmarked)
        case .conversationCreated(let dto):
            guard let conversation = mapper?.conversation(dto) else { return }
            insert(conversation, keepUnread: false)
            publishConversations()
            persistConversations()
        case .callStateChanged(let change):
            setCall(
                change.isLive ? change.roomId.map { CallRoom(roomId: $0, startedAt: change.startTime) } : nil,
                on: change.conversationId
            )
        case .adHocRemoved(let removal):
            setCall(nil, on: removal.conversationId)
        case .readReceipt(let receipt):
            // Other people's receipts are not rendered (03 §12). The viewer's own, from another
            // device, clears this conversation's delivered notifications (IF-07).
            if receipt.userId == viewer.id { conversationReadBroadcaster.send(receipt.conversationId) }
        case .readState(let state):
            if state.threadRootMessageId == nil { conversationReadBroadcaster.send(state.conversationId) }
        case .activity, .activityRemoved, .bookmark(nil), .notification, .taskComment:
            // These belong to other repositories.
            break
        }
    }

    private func ingest(_ dto: MessageSendResponse) async {
        guard var message = mapper?.message(dto) else { return }
        message.isNew = true
        let conversationId = message.conversationId
        reconcilePending(with: message)
        await typingTracker.messageArrived(conversationId: conversationId, authorId: message.authorId)
        upsert(message, fromRealtime: true)
        if let rootId = message.threadRootId, message.isThreadReply {
            // Read where it is seen: in its thread, never because the conversation is open (IF-02).
            if presence.isThreadActive(rootId), !message.isMine {
                await markRead(rootMessageId: rootId, conversationId: conversationId)
            }
            return
        }
        let isActive = presence.isActive(conversationId)
        if message.hasRenderableContent {
            applyToPreview(message, incrementUnread: !message.isMine && !isActive)
        } else {
            // A sparse event never overwrites a good preview; refetch instead (05 §5 step 7).
            Task { await self.refresh() }
        }
        if isActive, !message.isMine {
            try? await markRead(conversationId: conversationId)
        }
    }

    /// Merges a message into the inbox row, bumping it to the top (02 §2).
    func applyToPreview(_ message: ChatMessage, incrementUnread: Bool) {
        guard var row = conversationsById[message.conversationId] else {
            // A conversation the inbox has not seen yet.
            Task { await self.refresh() }
            return
        }
        row.lastMessage = Conversation.mergedPreview(current: row.lastMessage, newer: message)
        if incrementUnread { row.unreadCount += 1 }
        conversationsById[row.id] = row
        publishConversations()
        persistConversations()
    }

    private func setCall(_ room: CallRoom?, on conversationId: Int) {
        guard var row = conversationsById[conversationId], row.activeCall != room else { return }
        row.activeCall = room
        conversationsById[conversationId] = row
        publishConversations()
    }

    /// From the hub, a toggle or the bookmarks screen: patch every cached copy.
    public func applyBookmark(messageId: Int, isBookmarked: Bool) {
        let conversationIds = Set(timelines.keys).union(threads.values.map(\.conversationId))
        for conversationId in conversationIds where message(messageId, conversationId: conversationId) != nil {
            updateMessage(messageId, conversationId: conversationId) { message in
                var updated = message
                updated.isBookmarked = isBookmarked
                return updated
            }
        }
    }

    /// In-app alerts come from `ReceiveChatAttention`, where the server has already decided
    /// who should be alerted (gap G-09).
    private func alert(for dto: MessageSendResponse, reason: AttentionReason) {
        guard let message = mapper?.message(dto), !message.isMine, presence.isForeground,
            !presence.isActive(conversationId: message.conversationId, threadRootMessageId: message.threadRootId)
        else { return }
        let preferences = alertPreferences()
        guard preferences.inAppBanners else { return }
        let mappedReason: ChatAlert.Reason =
            switch reason {
            case .mention: .mention
            case .threadReply: .threadReply
            case .message, .unknown: .message
            }
        alertBroadcaster.send(
            ChatAlert(
                conversationId: message.conversationId,
                messageId: message.id,
                reason: mappedReason,
                title: conversationsById[message.conversationId]?.title,
                preview: preferences.previewContent ? message.bodyText : nil,
                destination: ChatDestination(message: message)
            )
        )
    }

    /// After every reconnect: typing cleared, inbox refetched, each open conversation's and
    /// thread's newest page merged, queued sends resumed (05 §2, PLAN parity fix).
    public func resync() async {
        await typingTracker.clearAll()
        // Closed conversations may have missed messages while the hub was down: their cache is
        // not trusted (or added to) until the next open refetches it (IF-01).
        for (conversationId, state) in timelines where state.isLoaded && openConversations[conversationId] == nil {
            timelines[conversationId]?.isStale = true
        }
        resumeOutbox()
        await refresh()
        for conversationId in openConversations.keys.sorted() {
            await refresh(conversationId: conversationId)
        }
        for (rootId, count) in openThreads where count > 0 {
            guard let conversationId = threads[rootId]?.conversationId else { continue }
            await refresh(rootMessageId: rootId, conversationId: conversationId)
        }
    }

    /// The app came to the foreground or left it. Conversations on screen count as read again,
    /// and queued sends get another try (IF-04, IF-07).
    public func foregroundChanged(_ isForeground: Bool) {
        presence.setForeground(isForeground)
        guard isForeground, viewer != nil else { return }
        for conversationId in presence.visibleConversationIds.sorted() {
            conversationReadBroadcaster.send(conversationId)
        }
        resumeOutbox()
    }

    public nonisolated func conversationsRead() -> AsyncStream<Int> { conversationReadBroadcaster.stream() }
    public nonisolated func alerts() -> AsyncStream<ChatAlert> { alertBroadcaster.stream() }
    public nonisolated func readStates() -> AsyncStream<ChatReadState> { readStateBroadcaster.stream() }
}
