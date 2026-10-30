import Foundation
import WaiveraAPI
import WaiveraRealtime

extension ChatEngine: ThreadsRepository {
    nonisolated public func thread(rootMessageId: Int, conversationId: Int) -> AsyncStream<Resource<ThreadTimeline>> {
        threadCells.cell(rootMessageId).stream()
    }

    /// Threads join the conversation's hub group too, so live replies arrive even when opened
    /// straight from a push (04 §4 fix). Joins are reference counted with the conversation;
    /// presence is not: only the thread counts as on screen (IF-02).
    public func open(rootMessageId: Int, conversationId: Int) async {
        openThreads[rootMessageId, default: 0] += 1
        presence.setThreadVisible(rootMessageId, true)
        if threads[rootMessageId] == nil {
            var state = ThreadState(conversationId: conversationId)
            state.root = timelines[conversationId]?.messages[rootMessageId]
            threads[rootMessageId] = state
        }
        await realtime.join(conversationId: conversationId)
        await refresh(rootMessageId: rootMessageId, conversationId: conversationId)
    }

    public func close(rootMessageId: Int, conversationId: Int) async {
        guard let count = openThreads[rootMessageId] else { return }
        openThreads[rootMessageId] = count > 1 ? count - 1 : nil
        presence.setThreadVisible(rootMessageId, false)
        await realtime.leave(conversationId: conversationId)
        await throttle.stop(conversationId: conversationId)
    }

    public func refresh(rootMessageId: Int, conversationId: Int) async {
        guard let mapper else { return }
        let current = generation
        threads[rootMessageId, default: ThreadState(conversationId: conversationId)].phase = .loading
        publishThread(rootMessageId)
        do {
            let rows = try await api.thread(rootMessageId: rootMessageId)
            guard generation == current, var state = threads[rootMessageId] else { return }
            for message in rows.compactMap({ mapper.message($0, conversationId: conversationId) }) {
                if message.id == rootMessageId {
                    state.root = state.root?.merging(message) ?? message
                } else {
                    state.replies[message.id] = state.replies[message.id]?.merging(message) ?? message
                }
                reconcilePending(with: message)
            }
            state.isLoaded = true
            state.phase = .loaded
            state.updatedAt = clock.now
            threads[rootMessageId] = state
            syncReplyCount(rootMessageId)
        } catch {
            guard generation == current else { return }
            threads[rootMessageId]?.phase = .failed(WaiveraError.from(error))
        }
        publishThread(rootMessageId)
    }

    @discardableResult
    public func reply(
        text: String,
        attachment: Attachment?,
        rootMessageId: Int,
        conversationId: Int
    ) async -> OutgoingMessage? {
        await throttle.stop(conversationId: conversationId)
        return await enqueue(
            text: text,
            attachment: attachment,
            conversationId: conversationId,
            parentMessageId: rootMessageId
        )
    }

    /// Read-through scoped to the thread (04 §4).
    public func markRead(rootMessageId: Int, conversationId: Int) async {
        guard let newest = threads[rootMessageId]?.replies.keys.max() ?? threads[rootMessageId]?.root?.id else {
            return
        }
        await readThrough(conversationId: conversationId, messageId: newest, threadRootMessageId: rootMessageId)
    }

    /// Stores a reply under its root; bumps the root's reply count only for a reply not seen
    /// before, so a repeat delivery never inflates it (04 §2).
    func storeThreadReply(_ reply: ChatMessage, countIfNew: Bool) {
        guard let rootId = reply.threadRootId else { return }
        var state = threads[rootId] ?? ThreadState(conversationId: reply.conversationId)
        let isNew = state.replies[reply.id] == nil
        state.replies[reply.id] = state.replies[reply.id]?.merging(reply) ?? reply
        if state.root == nil { state.root = timelines[reply.conversationId]?.messages[rootId] }
        threads[rootId] = state
        if isNew, countIfNew, var root = timelines[reply.conversationId]?.messages[rootId] {
            root.threadReplyCount = max(root.threadReplyCount + 1, state.replies.count)
            timelines[reply.conversationId]?.messages[rootId] = root
            threads[rootId]?.root = root
            publishTimeline(reply.conversationId)
        }
        publishThread(rootId)
    }

    /// After a full thread fetch the count is known exactly.
    private func syncReplyCount(_ rootId: Int) {
        guard let state = threads[rootId], state.isLoaded,
            var root = timelines[state.conversationId]?.messages[rootId], root.threadReplyCount != state.replies.count
        else { return }
        root.threadReplyCount = state.replies.count
        timelines[state.conversationId]?.messages[rootId] = root
        publishTimeline(state.conversationId)
    }
}
