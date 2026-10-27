import Foundation
import WaiveraAPI
import WaiveraRealtime

/// Saved messages with the degraded per-conversation path for when `/api/chat/bookmarks`
/// fails on legacy rows (gap G-04, 06 §B1).
public actor LiveBookmarksRepository: BookmarksRepository {
    static let fallbackWorkers = 4
    static let fallbackPageSize = 50

    private let api: APIClient
    private let context: SessionContext
    private let chat: ChatEngine
    private let clock: any WaiveraClock
    private let cell = StateCell(Resource<BookmarkList>())
    private var list: BookmarkList?
    private var phase: ResourcePhase = .idle
    private var updatedAt: Date?
    private var loading: Task<Void, Never>?
    private var generation = 0

    public init(api: APIClient, context: SessionContext, chat: ChatEngine, clock: any WaiveraClock) {
        self.api = api
        self.context = context
        self.chat = chat
        self.clock = clock
    }

    public nonisolated func bookmarks() -> AsyncStream<Resource<BookmarkList>> { cell.stream() }

    public func reset() {
        generation += 1
        loading?.cancel()
        loading = nil
        list = nil
        phase = .idle
        updatedAt = nil
        cell.set(Resource())
    }

    public func refresh() async {
        if let loading {
            await loading.value
            return
        }
        let task = Task { await self.load() }
        loading = task
        await task.value
        loading = nil
    }

    /// Leaving the screen stops a slow fallback walk.
    public func cancelRefresh() {
        loading?.cancel()
    }

    private func load() async {
        guard let viewer = context.currentUser else { return }
        let mapper = ChatMapper(viewerId: viewer.id)
        let current = generation
        phase = .loading
        publish()
        do {
            let rows: [MessageSendResponse]
            var usedFallback = false
            do {
                rows = try await api.bookmarks()
            } catch {
                guard !(error is CancellationError) else { throw error }
                rows = try await fallbackBookmarks(originalError: error)
                usedFallback = true
            }
            guard generation == current, !Task.isCancelled else { return }
            let messages = rows.compactMap { mapper.message($0) }
            var seen = Set<Int>()
            let bookmarks = messages.filter { seen.insert($0.id).inserted }
                .sorted { ($0.createdAt ?? .distantPast, $0.id) > ($1.createdAt ?? .distantPast, $1.id) }
                .map(Bookmark.init)
            list = BookmarkList(bookmarks: bookmarks, usedFallback: usedFallback)
            phase = .loaded
            updatedAt = clock.now
        } catch {
            guard generation == current else { return }
            phase = .failed(WaiveraError.from(error))
        }
        publish()
    }

    /// Walks every conversation's bookmarked search pages with four workers; rethrows the
    /// original error if the walk fails too.
    private func fallbackBookmarks(originalError: any Error) async throws -> [MessageSendResponse] {
        let api = api
        let conversationIds: [Int]
        do {
            conversationIds = try await api.myConversations(includeMeetings: false).map(\.id)
        } catch {
            throw originalError
        }
        let queue = WorkQueue(conversationIds)
        do {
            return try await withThrowingTaskGroup(of: [MessageSendResponse].self) { group in
                for _ in 0..<Self.fallbackWorkers {
                    group.addTask {
                        var found: [MessageSendResponse] = []
                        while let conversationId = queue.next() {
                            try Task.checkCancellation()
                            found += try await Self.allBookmarkPages(api: api, conversationId: conversationId)
                        }
                        return found
                    }
                }
                var all: [MessageSendResponse] = []
                for try await rows in group { all += rows }
                return all
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw originalError
        }
    }

    private static func allBookmarkPages(api: APIClient, conversationId: Int) async throws -> [MessageSendResponse] {
        var page = 1
        var rows: [MessageSendResponse] = []
        while true {
            let query = ChatSearchQuery(bookmarkedOnly: true, pageIndex: page, pageSize: fallbackPageSize)
            let batch = try await api.searchConversation(conversationId, query: query)
            rows += batch.map { row in
                var row = row
                row.conversationId = row.conversationId ?? conversationId
                return row
            }
            guard batch.count >= fallbackPageSize else { return rows }
            page += 1
        }
    }

    @discardableResult
    public func toggle(messageId: Int, conversationId: Int) async throws -> Bool {
        let isBookmarked: Bool
        do {
            isBookmarked = try await api.toggleBookmark(messageId: messageId)
        } catch {
            throw WaiveraError.from(error)
        }
        await chat.applyBookmark(messageId: messageId, isBookmarked: isBookmarked)
        await apply(messageId: messageId, conversationId: conversationId, isBookmarked: isBookmarked)
        return isBookmarked
    }

    /// Hub `ReceiveBookmarkUpdate`; a shapeless event refetches (05 §6).
    public func handle(_ update: BookmarkUpdateEvent?) async {
        guard let update else {
            await refresh()
            return
        }
        await apply(messageId: update.messageId, conversationId: nil, isBookmarked: update.isBookmarked)
    }

    private func apply(messageId: Int, conversationId: Int?, isBookmarked: Bool) async {
        guard var current = list else { return }
        if isBookmarked {
            guard !current.bookmarks.contains(where: { $0.id == messageId }) else { return }
            guard let conversationId, let message = await chat.message(messageId, conversationId: conversationId) else {
                await refresh()
                return
            }
            current.bookmarks.insert(Bookmark(message: message), at: 0)
        } else {
            current.bookmarks.removeAll { $0.id == messageId }
        }
        list = current
        publish()
    }

    private func publish() {
        cell.set(Resource(value: list, phase: phase, updatedAt: updatedAt))
    }
}

/// A shared cursor over conversation ids for the fallback workers.
private final class WorkQueue: Sendable {
    private let remaining: LockedValue<[Int]>

    init(_ ids: [Int]) {
        remaining = LockedValue(ids.reversed())
    }

    func next() -> Int? {
        remaining.update { $0.popLast() }
    }
}
