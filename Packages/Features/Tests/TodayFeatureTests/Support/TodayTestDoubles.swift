import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import TodayFeature

/// An activity feed served in pages, like the live repository: `refresh` loads page 1,
/// `loadMore` appends the next page, and reads are optimistic, restored when they fail.
/// `FakeActivityRepository` records `loadMore` without paging (docs/requests/today.md §7).
final class PagedActivityRepository: ActivityRepository {
    private struct State {
        var pages: [[ActivityItem]]
        var loadedPages = 0
        var endless: Bool
        var loadMoreFailure: WaiveraError?
        var readFailure: WaiveraError?
    }

    let calls = CallLog()
    private let state: LockedValue<State>
    private let cell = StateCell(Resource<ActivityFeed>())
    private let clock: any WaiveraClock

    /// `endless` keeps producing full unread pages after `pages` run out.
    init(pages: [[ActivityItem]], endless: Bool = false, clock: any WaiveraClock) {
        state = LockedValue(State(pages: pages, endless: endless))
        self.clock = clock
    }

    static func page(_ number: Int, count: Int = ActivityRules.pageSize, isRead: Bool = false) -> [ActivityItem] {
        (0..<count).map { offset in
            let id = Int64(number * 1_000 + offset)
            var item = Fixture.activity(id, .threadReply, at: nil, isRead: isRead)
            // Older pages are older: page 1 is newest.
            item.createdAt = Fixture.now.addingTimeInterval(-Double(number * 10_000 + offset * 60))
            return item
        }
    }

    func setLoadMoreFailure(_ failure: WaiveraError?) { state.update { $0.loadMoreFailure = failure } }
    func setReadFailure(_ failure: WaiveraError?) { state.update { $0.readFailure = failure } }
    var current: Resource<ActivityFeed> { cell.current }

    func feed() -> AsyncStream<Resource<ActivityFeed>> { cell.stream() }

    func refresh() async {
        calls.record("refresh")
        let first = state.update { state -> (items: [ActivityItem], hasMore: Bool) in
            state.loadedPages = 1
            return (state.pages.first ?? [], Self.hasMore(state))
        }
        cell.set(
            Resource(
                value: ActivityFeed(items: first.items, hasMore: first.hasMore),
                phase: .loaded,
                updatedAt: clock.now
            )
        )
    }

    func loadMore() async {
        calls.record("loadMore")
        let next = state.update { state -> (items: [ActivityItem], hasMore: Bool)? in
            if state.loadMoreFailure != nil { return nil }
            let index = state.loadedPages
            let items = index < state.pages.count ? state.pages[index] : (state.endless ? Self.page(index + 1) : [])
            state.loadedPages += 1
            return (items, Self.hasMore(state))
        }
        guard let next else {
            if let failure = state.get().loadMoreFailure { cell.update { $0.phase = .failed(failure) } }
            return
        }
        cell.update { resource in
            var feed = resource.value ?? ActivityFeed()
            feed.items += next.items
            feed.hasMore = next.hasMore
            resource.value = feed
            resource.phase = .loaded
        }
    }

    func markRead(activityId: Int64) async throws {
        calls.record("markRead:\(activityId)")
        try await apply { feed in
            for index in feed.items.indices where feed.items[index].id == activityId { feed.items[index].isRead = true }
        }
    }

    func markAllRead() async throws {
        calls.record("markAllRead")
        try await apply { feed in
            for index in feed.items.indices { feed.items[index].isRead = true }
        }
    }

    private func apply(_ change: (inout ActivityFeed) -> Void) async throws {
        let before = cell.current.value
        cell.update { resource in
            guard var feed = resource.value else { return }
            change(&feed)
            resource.value = feed
        }
        await Task.yield()
        if let failure = state.get().readFailure {
            cell.update { $0.value = before }
            throw failure
        }
    }

    private static func hasMore(_ state: State) -> Bool {
        state.endless || state.loadedPages < state.pages.count
    }
}

/// An inbox whose rows and failures the test sets directly.
final class StubConversations: ConversationsRepository {
    let rows: LockedValue<[Conversation]>
    let failure = LockedValue<WaiveraError?>(nil)
    let calls = CallLog()
    private let cell = StateCell(Resource<[Conversation]>())
    private let clock: any WaiveraClock

    init(_ rows: [Conversation], clock: any WaiveraClock) {
        self.rows = LockedValue(rows)
        self.clock = clock
    }

    func conversations() -> AsyncStream<Resource<[Conversation]>> { cell.stream() }

    func refresh() async {
        calls.record("refresh")
        if let failure = failure.get() {
            cell.update { $0.phase = .failed(failure) }
        } else {
            cell.set(Resource(value: rows.get(), phase: .loaded, updatedAt: clock.now))
        }
    }

    func conversation(id: Int) async throws -> Conversation {
        guard let row = rows.get().first(where: { $0.id == id }) else { throw WaiveraError.notFound }
        return row
    }

    func typing() -> AsyncStream<[Int: [String]]> { StateCell([Int: [String]]()).stream() }
    func totalUnread() -> AsyncStream<Int> { StateCell(0).stream() }
    func openDirectConversation(with userId: String) async throws -> Conversation { throw WaiveraError.notFound }
    func createConversation(participantIds: [String]) async throws -> Conversation { throw WaiveraError.notFound }
    func leave(conversationId: Int) async throws { throw WaiveraError.notFound }
}

/// A monotonic uptime the test moves by hand, for the navigation guard.
final class ManualUptime: Sendable {
    private let value = LockedValue<TimeInterval>(100)

    var now: TimeInterval { value.get() }
    func advance(by seconds: TimeInterval) { value.update { $0 += seconds } }
}

/// The fake world with any repository swapped for a test double.
struct TodayHarness {
    let fakes: FakeDataEnvironment
    let clock: ManualClock
    let environment: DataEnvironment
    let uptime = ManualUptime()

    init(
        _ scenario: FakeDataEnvironment.Scenario = .demo,
        clock: ManualClock = ManualClock(now: Fixture.now),
        conversations: [Conversation]? = nil,
        activity: (any ActivityRepository)? = nil,
        events: [CalendarEvent]? = nil,
        milestones: [Milestone]? = nil
    ) {
        let fakes = FakeDataEnvironment.make(scenario, clock: clock)
        var calendar = fakes.calendar
        if events != nil || milestones != nil {
            var data = fakes.data
            if let events { data.calendar = CalendarFeed(events: events) }
            if let milestones { data.milestones = milestones }
            calendar = FakeCalendarRepository(data: data, clock: clock)
        }
        self.clock = clock
        self.fakes = fakes
        self.calendar = calendar
        environment = DataEnvironment(
            session: fakes.session,
            conversations: conversations.map { StubConversations($0, clock: clock) } ?? fakes.chat,
            messages: fakes.chat,
            threads: fakes.chat,
            attachments: fakes.attachments,
            avatars: FakeAvatarRepository(),
            bookmarks: fakes.bookmarks,
            activity: activity ?? fakes.activity,
            people: fakes.people,
            calendar: calendar,
            profile: fakes.profile,
            settings: fakes.settings,
            push: fakes.push,
            realtimeStatus: fakes.realtimeStatus,
            alerts: fakes.alerts,
            callURL: { _ in throw WaiveraError.configurationMissing },
            foreground: { _ in },
            start: {}
        )
    }

    /// The handled tally's storage, in memory so tests never touch the device's defaults.
    let handledStore = KeyValueHandledTallyStore(store: InMemoryKeyValueStore())

    /// The calendar in use: the demo one, or one built from the events passed in.
    let calendar: FakeCalendarRepository

    var stubConversations: StubConversations? { environment.conversations as? StubConversations }

    @MainActor
    func todayModel() -> TodayModel {
        let uptime = uptime
        return TodayModel(
            environment: environment,
            clock: clock,
            uptime: { uptime.now },
            handledStore: handledStore
        )
    }

    @MainActor
    func activityModel() -> ActivityFeedModel {
        let uptime = uptime
        return ActivityFeedModel(environment: environment, clock: clock, uptime: { uptime.now })
    }
}

/// Polls `condition` on the main actor until it holds or two seconds pass.
@MainActor
func eventually(timeout: Duration = .seconds(2), _ condition: () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while !condition() {
        if ContinuousClock.now >= deadline { return false }
        try? await Task.sleep(for: .milliseconds(2))
    }
    return true
}

/// Lets queued main-actor work run, for checks that something did not happen.
@MainActor
func settle() async {
    for _ in 0..<50 { await Task.yield() }
    try? await Task.sleep(for: .milliseconds(20))
}
