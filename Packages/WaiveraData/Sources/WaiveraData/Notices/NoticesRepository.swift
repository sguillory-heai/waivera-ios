import Foundation
import WaiveraAPI

/// The web bell's notifications (Android `NoticeRepository`).
public protocol NoticesRepository: Sendable {
    func feed() -> AsyncStream<Resource<NoticeFeed>>
    func refresh() async
    /// Optimistic; restores the row and throws when the server call fails.
    func markRead(id: String) async throws
    func markAllRead() async throws
    /// Another device read it (`ReceiveNotificationRead`, or a `notification.read` push). `nil` is all.
    func readElsewhere(notificationId: String?) async
    /// Ids read here or elsewhere (`nil` for all), so the shell can clear their delivered alerts.
    func reads() -> AsyncStream<String?>
}

/// The live inbox, held in memory: the server is the record and the list is short, so a cold
/// start shows the skeleton for one call instead of a stale copy. The unread count is the
/// server's own, so it includes rows older than the first page.
public actor LiveNoticesRepository: NoticesRepository {
    private let api: APIClient
    private let clock: any WaiveraClock
    private let cell = StateCell(Resource<NoticeFeed>())
    private let readEvents = AsyncBroadcaster<String?>(replays: false, keepsEveryValue: true)
    private var feedValue: NoticeFeed?
    private var phase: ResourcePhase = .idle
    private var updatedAt: Date?
    /// Bumped on sign-out, so a fetch still in flight never writes the last account's list back.
    private var generation = 0
    /// The refresh in flight, and whether one more was asked for while it ran: a new row that
    /// arrives mid-fetch may be missing from that page, so it gets one follow-up, not a drop.
    private var refreshing: Task<Void, Never>?
    private var refreshAgain = false
    /// Read here but maybe not yet on the server's page; kept read until a page agrees.
    private var readLocally: Set<String> = []
    /// Read on another device: a failed local read never undoes them.
    private var readOnOtherDevice: Set<String> = []

    public init(api: APIClient, clock: any WaiveraClock) {
        self.api = api
        self.clock = clock
    }

    nonisolated public func feed() -> AsyncStream<Resource<NoticeFeed>> { cell.stream() }
    nonisolated public func reads() -> AsyncStream<String?> { readEvents.stream() }

    /// Callers that ask while a fetch runs wait for one follow-up fetch, shared by all of them.
    public func refresh() async {
        if let refreshing {
            refreshAgain = true
            await refreshing.value
            return
        }
        let task = Task { await self.refreshUntilSettled() }
        refreshing = task
        await task.value
    }

    private func refreshUntilSettled() async {
        repeat {
            refreshAgain = false
            await fetchOnce()
        } while refreshAgain
        refreshing = nil
    }

    private func fetchOnce() async {
        let started = generation
        phase = .loading
        publish()
        do {
            let items = try await api.notifications().compactMap(NoticeMapping.notice)
            // The count is a nicety: when it fails the page's own unread rows stand in.
            let unread = try? await api.notificationUnreadCount()
            guard generation == started else { return }
            feedValue = merged(NoticeFeed(items: items, unreadCount: unread ?? items.filter { !$0.isRead }.count))
            phase = .loaded
            updatedAt = clock.now
        } catch {
            guard generation == started else { return }
            phase = .failed(WaiveraError.from(error))
        }
        publish()
    }

    /// The fetched page, keeping what changed on the phone while it was in flight.
    private func merged(_ fetched: NoticeFeed) -> NoticeFeed {
        let agreed = Set(fetched.items.filter(\.isRead).map(\.id))
        readLocally.subtract(agreed)
        readOnOtherDevice.subtract(agreed)
        let stale = fetched.items.filter { readLocally.contains($0.id) && !$0.isRead }.count
        var items = fetched.items
        for index in items.indices where readLocally.contains(items[index].id) { items[index].isRead = true }
        return NoticeFeed(items: items, unreadCount: max(0, fetched.unreadCount - stale))
    }

    public func markRead(id: String) async throws {
        guard let feed = feedValue, feed.items.contains(where: { $0.id == id && !$0.isRead }) else { return }
        readLocally.insert(id)
        feedValue = feed.markingRead([id])
        publish()
        readEvents.send(id)
        do {
            try await api.markNotificationRead(id: id)
        } catch {
            rollBack([id])
            throw WaiveraError.from(error)
        }
    }

    public func markAllRead() async throws {
        guard let feed = feedValue else { return }
        let unreadIds = Set(feed.items.filter { !$0.isRead }.map(\.id))
        let unreadBefore = feed.unreadCount
        guard unreadBefore > 0 || !unreadIds.isEmpty else { return }
        readLocally.formUnion(unreadIds)
        var read = feed
        for index in read.items.indices { read.items[index].isRead = true }
        read.unreadCount = 0
        feedValue = read
        publish()
        readEvents.send(nil)
        do {
            try await api.markAllNotificationsRead()
        } catch {
            let undo = unreadIds.subtracting(readOnOtherDevice)
            readLocally.subtract(undo)
            if var current = feedValue {
                for index in current.items.indices where undo.contains(current.items[index].id) {
                    current.items[index].isRead = false
                }
                current.unreadCount = unreadBefore - (unreadIds.count - undo.count)
                feedValue = current
            }
            publish()
            throw WaiveraError.from(error)
        }
    }

    public func readElsewhere(notificationId: String?) async {
        let feed = feedValue ?? NoticeFeed()
        let ids = notificationId.map { [$0] } ?? Set(feed.items.filter { !$0.isRead }.map(\.id))
        readLocally.formUnion(ids)
        readOnOtherDevice.formUnion(ids)
        if feedValue != nil {
            if notificationId == nil {
                var read = feed
                for index in read.items.indices { read.items[index].isRead = true }
                read.unreadCount = 0
                feedValue = read
            } else {
                // A row outside the loaded page waits for the next refresh to correct the count.
                feedValue = feed.markingRead(ids)
            }
            publish()
        }
        readEvents.send(notificationId)
    }

    /// Sign-out.
    public func reset() {
        generation += 1
        readLocally.removeAll()
        readOnOtherDevice.removeAll()
        feedValue = nil
        phase = .idle
        updatedAt = nil
        cell.set(Resource())
    }

    private func rollBack(_ ids: Set<String>) {
        let undo = ids.subtracting(readOnOtherDevice)
        readLocally.subtract(undo)
        guard var current = feedValue else { return }
        var restored = 0
        for index in current.items.indices where undo.contains(current.items[index].id) && current.items[index].isRead {
            current.items[index].isRead = false
            restored += 1
        }
        current.unreadCount += restored
        feedValue = current
        publish()
    }

    private func publish() {
        cell.set(Resource(value: feedValue, phase: phase, updatedAt: updatedAt))
    }
}

/// For environments without an inbox (older fakes, tests that do not need one).
public struct EmptyNoticesRepository: NoticesRepository {
    public init() {}
    public func feed() -> AsyncStream<Resource<NoticeFeed>> {
        AsyncStream { continuation in
            continuation.yield(Resource(value: NoticeFeed(), phase: .loaded))
            continuation.finish()
        }
    }
    public func refresh() async {}
    public func markRead(id: String) async throws {}
    public func markAllRead() async throws {}
    public func readElsewhere(notificationId: String?) async {}
    public func reads() -> AsyncStream<String?> { AsyncStream { $0.finish() } }
}
