import Foundation
import WaiveraAPI
import WaiveraRealtime

extension ChatEngine: ConversationsRepository {
    public nonisolated func conversations() -> AsyncStream<Resource<[Conversation]>> { conversationsCell.stream() }
    public nonisolated func typing() -> AsyncStream<[Int: [String]]> { typingTracker.cell.stream() }
    public nonisolated func totalUnread() -> AsyncStream<Int> { unreadCell.stream() }
    public nonisolated func failedSends() -> AsyncStream<Set<Int>> { failedSendsCell.stream() }

    /// Concurrent callers share one request.
    public func refresh() async {
        if let running = conversationsLoad {
            await running.value
            return
        }
        let task = Task { await self.loadConversations() }
        conversationsLoad = task
        await task.value
        conversationsLoad = nil
    }

    func loadConversations() async {
        guard let mapper else { return }
        let current = generation
        conversationsPhase = .loading
        publishConversations()
        do {
            // `/api/chat/all` with both flags explicit (gap G-13).
            let rows = try await api.allConversations(includeArchived: false)
            guard generation == current else { return }
            var next: [Int: Conversation] = [:]
            for dto in rows {
                guard let fresh = mapper.conversation(dto) else { continue }
                next[fresh.id] =
                    conversationsById[fresh.id].map { Self.mergeListRow(current: $0, fresh: fresh) } ?? fresh
            }
            conversationsById = next
            conversationsPhase = .loaded
            conversationsUpdatedAt = clock.now
            publishConversations()
            persistConversations()
            await hydrateSparsePreviews(generation: current)
        } catch {
            guard generation == current else { return }
            conversationsPhase = .failed(WaiveraError.from(error))
            publishConversations()
        }
    }

    /// The list is authoritative for unread and calls; the preview keeps richer cached fields.
    static func mergeListRow(current: Conversation, fresh: Conversation) -> Conversation {
        var merged = fresh
        merged.lastMessage = Conversation.mergedPreview(current: current.lastMessage, newer: fresh.lastMessage)
        if fresh.participants.isEmpty { merged.participants = current.participants }
        merged.channel = fresh.channel ?? current.channel
        return merged
    }

    /// Rows whose preview is blank are filled from the detail endpoint in batches of six
    /// (02 §2). Failures leave the row as it is.
    func hydrateSparsePreviews(generation current: Int) async {
        let sparse = conversationsById.values.filter { $0.lastMessage != nil && $0.preview.needsHydration }.map(\.id)
            .sorted()
        guard let mapper, !sparse.isEmpty else { return }
        let api = api
        for start in stride(from: 0, to: sparse.count, by: Self.hydrationBatchSize) {
            let batch = sparse[start..<min(start + Self.hydrationBatchSize, sparse.count)]
            let details = await withTaskGroup(of: Conversation?.self) { group in
                for id in batch {
                    group.addTask { (try? await api.conversation(id: id)).flatMap(mapper.conversation) }
                }
                var results: [Conversation] = []
                for await detail in group { if let detail { results.append(detail) } }
                return results
            }
            guard generation == current else { return }
            for detail in details { insert(detail, keepUnread: true) }
            publishConversations()
        }
        persistConversations()
    }

    /// Merges a detail payload; the detail endpoint's unread count is not trusted (G-14).
    func insert(_ conversation: Conversation, keepUnread: Bool) {
        if let existing = conversationsById[conversation.id] {
            conversationsById[conversation.id] = existing.merging(detail: conversation, keepUnread: keepUnread)
        } else {
            conversationsById[conversation.id] = conversation
        }
    }

    public func conversation(id: Int) async throws -> Conversation {
        if let cached = conversationsById[id] { return cached }
        guard let mapper else { throw WaiveraError.signedOut }
        let current = generation
        guard let detail = mapper.conversation(try await api.conversation(id: id)) else {
            throw WaiveraError.invalidResponse
        }
        guard generation == current else { throw WaiveraError.signedOut }
        insert(detail, keepUnread: false)
        publishConversations()
        return conversationsById[id] ?? detail
    }

    public func openDirectConversation(with userId: String) async throws -> Conversation {
        guard mapper != nil else { throw WaiveraError.signedOut }
        let current = generation
        let dto = try await api.privateConversation(with: userId)
        return try adopt(dto, startedIn: current)
    }

    public func createConversation(participantIds: [String]) async throws -> Conversation {
        guard mapper != nil else { throw WaiveraError.signedOut }
        let current = generation
        let dto = try await api.createConversation(participantIds: participantIds)
        return try adopt(dto, startedIn: current)
    }

    /// The get-or-create endpoints fill only `id` and `participants`; merge into the cache.
    /// A reply that lands after a sign-out, or after someone else signed in, belongs to the
    /// session that asked, so it is dropped rather than written into the next person's inbox
    /// (PS-01). A chat the signed-in person is not in is never cached either.
    private func adopt(_ dto: ConversationResponse, startedIn requestGeneration: Int) throws -> Conversation {
        guard generation == requestGeneration, let mapper else { throw WaiveraError.signedOut }
        guard let conversation = mapper.conversation(dto) else { throw WaiveraError.invalidResponse }
        guard conversation.participants.isEmpty || conversation.participants.contains(where: { $0.id == mapper.viewerId })
        else { throw WaiveraError.invalidResponse }
        insert(conversation, keepUnread: true)
        publishConversations()
        persistConversations()
        return conversationsById[conversation.id] ?? conversation
    }

    public func leave(conversationId: Int) async throws {
        try await api.leaveConversation(conversationId: conversationId)
        conversationsById[conversationId] = nil
        publishConversations()
        persistConversations()
    }

    /// Unread to zero and `lastReadAt` to now, only when there was something unread (02 §2).
    func clearUnread(_ conversationId: Int) {
        guard var row = conversationsById[conversationId], row.unreadCount > 0 else { return }
        row.unreadCount = 0
        row.lastReadAt = clock.now
        conversationsById[conversationId] = row
        publishConversations()
        persistConversations()
    }
}
