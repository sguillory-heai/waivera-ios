import Foundation
import WaiveraAPI
import WaiveraRealtime

/// The activity feed (06 §A): pages of 30, de-duplicated by id, newest first by parsed
/// instant, with optimistic read state and live hub updates.
public actor LiveActivityRepository: ActivityRepository {
    public static let pageSize = 30

    private let api: APIClient
    private let store: any LocalStore
    private let clock: any WaiveraClock
    private let cell = StateCell(Resource<ActivityFeed>())
    private var items: [Int64: ActivityItem] = [:]
    private var nextPage = 1
    private var hasMore = false
    private var isLoadingMore = false
    private var loadMoreError: WaiveraError?
    /// Bumped by every page-1 load, so an older page that lands afterwards is dropped.
    private var pageEpoch = 0
    private var phase: ResourcePhase = .idle
    private var updatedAt: Date?
    private var generation = 0
    private let mapper = ChatMapper(viewerId: "")
    private let writes = SerialQueue()

    public init(api: APIClient, store: any LocalStore, clock: any WaiveraClock) {
        self.api = api
        self.store = store
        self.clock = clock
    }

    nonisolated public func feed() -> AsyncStream<Resource<ActivityFeed>> { cell.stream() }

    public func begin() async {
        guard let cached = await store.load([ActivityItem].self, for: .activity), items.isEmpty else { return }
        for item in cached { items[item.id] = item }
        publish()
    }

    /// Sign-out: drops state and waits for queued cache writes so none lands after the wipe.
    public func reset() async {
        generation += 1
        items.removeAll()
        nextPage = 1
        hasMore = false
        isLoadingMore = false
        loadMoreError = nil
        phase = .idle
        updatedAt = nil
        cell.set(Resource())
        await writes.drain()
    }

    public func refresh() async {
        let current = generation
        pageEpoch += 1
        let epoch = pageEpoch
        phase = .loading
        publish()
        do {
            let rows = try await api.recentActivity(page: 1, pageSize: Self.pageSize)
            guard generation == current, pageEpoch == epoch else { return }
            items = Dictionary(rows.compactMap(mapper.activity).map { ($0.id, $0) }, uniquingKeysWith: { $1 })
            nextPage = 2
            hasMore = rows.count >= Self.pageSize
            isLoadingMore = false
            loadMoreError = nil
            phase = .loaded
            updatedAt = clock.now
            persist()
        } catch {
            guard generation == current, pageEpoch == epoch else { return }
            phase = .failed(WaiveraError.from(error))
        }
        publish()
    }

    /// One page at a time: a call while a page is in flight returns at once. A failure keeps
    /// the loaded pages and phase, sets `loadMoreError`, and the next call retries that page.
    public func loadMore() async {
        guard hasMore, !isLoadingMore, updatedAt != nil else { return }
        let current = generation
        let epoch = pageEpoch
        let page = nextPage
        isLoadingMore = true
        loadMoreError = nil
        publish()
        do {
            let rows = try await api.recentActivity(page: page, pageSize: Self.pageSize)
            guard generation == current, pageEpoch == epoch else { return }
            for item in rows.compactMap(mapper.activity) { items[item.id] = item }
            nextPage = page + 1
            hasMore = rows.count >= Self.pageSize
            persist()
        } catch {
            guard generation == current, pageEpoch == epoch else { return }
            loadMoreError = WaiveraError.from(error)
        }
        isLoadingMore = false
        publish()
    }

    public func markRead(activityId: Int64) async throws {
        guard items[activityId]?.isRead == false else { return }
        setRead(true, where: { $0.id == activityId })
        do {
            try await api.markActivityRead(activityId: activityId)
        } catch {
            items[activityId]?.isRead = false
            publish()
            persist()
            throw WaiveraError.from(error)
        }
    }

    public func markAllRead() async throws {
        let snapshot = items
        setRead(true, where: { _ in true })
        do {
            try await api.markAllActivityRead()
        } catch {
            for (id, item) in snapshot where !item.isRead { items[id]?.isRead = false }
            publish()
            persist()
            throw WaiveraError.from(error)
        }
    }

    // MARK: Realtime

    public func handle(_ event: ChatHubEvent) {
        switch event {
        case .activity(let dto):
            guard let item = mapper.activity(dto) else { return }
            items[item.id] = item
            publish()
            persist()
        case .activityRemoved(let id):
            guard items.removeValue(forKey: id) != nil else { return }
            publish()
            persist()
        case .readState(let state):
            apply(state)
        default:
            break
        }
    }

    /// `ReceiveChatReadState` and read-through responses (05 §6). `conversationId == 0` is
    /// read-all for the listed ids.
    public func apply(_ state: ChatReadState) {
        let ids = Set(state.readActivityIds ?? [])
        setRead(true) { item in
            ids.contains(item.id)
                || (state.conversationId == item.conversationId && state.lastVisibleMessageId == item.messageId)
        }
    }

    private func setRead(_ read: Bool, where predicate: (ActivityItem) -> Bool) {
        var changed = false
        for (id, item) in items where item.isRead != read && predicate(item) {
            items[id]?.isRead = read
            changed = true
        }
        if changed {
            publish()
            persist()
        }
    }

    private func publish() {
        let sorted = items.values.sorted { lhs, rhs in
            switch (lhs.createdAt, rhs.createdAt) {
            case (let left?, let right?) where left != right: left > right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.id > rhs.id
            }
        }
        let value: ActivityFeed? =
            phase == .idle && sorted.isEmpty
            ? nil
            : ActivityFeed(
                items: sorted,
                hasMore: hasMore,
                isLoadingMore: isLoadingMore,
                loadMoreError: loadMoreError
            )
        cell.set(Resource(value: value, phase: phase, updatedAt: updatedAt))
    }

    private func persist() {
        let snapshot = Array(items.values)
        let store = store
        writes.enqueue { await store.save(snapshot, for: .activity) }
    }
}
