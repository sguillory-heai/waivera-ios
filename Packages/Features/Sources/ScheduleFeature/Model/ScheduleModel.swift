import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// The feed a period needs: two keys are equal when they fetch the same range in the same zone,
/// so picking another day in the same month does not restart the subscription.
public struct FeedKey: Sendable, Hashable {
    public let view: CalendarPeriod
    /// The selected date the repository is asked about; not part of equality.
    public let anchor: CalendarDate
    public let interval: DateInterval
    public let zoneIdentifier: String

    public static func == (lhs: FeedKey, rhs: FeedKey) -> Bool {
        lhs.view == rhs.view && lhs.interval == rhs.interval && lhs.zoneIdentifier == rhs.zoneIdentifier
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(view)
        hasher.combine(interval)
        hasher.combine(zoneIdentifier)
    }
}

/// The Schedule tab (07 §1–3, §8). Every boundary (the fetched range, the agenda day, "today"
/// and milestone matching) is computed in the employee's saved zone, never the device zone.
///
/// The view runs `start()` in a `.task` and `observeFeed()` in a `.task(id: feedKey)`, so
/// SwiftUI owns and cancels both.
@MainActor
@Observable
public final class ScheduleModel {
    /// The feed is refetched on appearance when older than this (Expo `staleTime: 60_000`).
    static let feedStaleAfter: TimeInterval = 60
    /// Milestones refresh on open when older than this (Expo `staleTime: 15 minutes`).
    static let milestonesStaleAfter: TimeInterval = 15 * 60

    public private(set) var state: ScheduleUIState
    public private(set) var view: CalendarPeriod = .month
    private var selection: CalendarDate?
    private var now: Date
    private var zone: ScheduleZone
    private var feedSnapshot: (key: FeedKey, resource: Resource<CalendarFeed>)?
    private var milestoneResource = Resource<MilestoneIndex>()
    private var isOffline = false
    private var myUserId: String?
    /// The celebrant whose chat "Send wishes" is opening; one at a time.
    private var openingWishesFor: String?
    /// The chat "Send wishes" opened, for the view to navigate to once.
    public private(set) var wishesRequest: WishesRequest?
    /// "Send wishes" could not open the chat; the view shows a snackbar with Retry.
    public private(set) var wishesFailure: WishesFailure?

    @ObservationIgnored private var milestoneCalendar = MilestoneCalendar.empty
    @ObservationIgnored private var text: ScheduleText
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private var wishesTask: Task<Void, Never>?
    @ObservationIgnored private var requestCount = 0

    private let calendar: any CalendarRepository
    private let session: any SessionRepository
    private let realtime: any RealtimeStatusRepository
    private let conversations: (any ConversationsRepository)?
    private let clock: any WaiveraClock
    private let deviceZone: @Sendable () -> TimeZone
    private let locale: Locale

    public init(
        calendar: any CalendarRepository,
        session: any SessionRepository,
        realtime: any RealtimeStatusRepository,
        conversations: (any ConversationsRepository)? = nil,
        clock: any WaiveraClock = SystemClock(),
        deviceZone: @escaping @Sendable () -> TimeZone = { TimeZone.current },
        locale: Locale = .autoupdatingCurrent
    ) {
        self.calendar = calendar
        self.session = session
        self.realtime = realtime
        self.conversations = conversations
        self.clock = clock
        self.deviceZone = deviceZone
        self.locale = locale
        let zone = ScheduleZone.resolve(savedIdentifier: session.currentState.user?.timeZoneIdentifier)
        let text = ScheduleText(zone: zone.timeZone, locale: locale)
        let now = clock.now
        let me = session.currentState.user?.id
        myUserId = me
        self.zone = zone
        self.text = text
        self.now = now
        let today = CalendarDate(now, in: zone.timeZone)
        state = ScheduleStateBuilder(
            view: .month,
            selectedDate: today,
            today: today,
            zone: zone,
            deviceZone: deviceZone(),
            feed: nil,
            milestones: .empty,
            milestonesFailed: false,
            isOffline: false,
            now: now,
            myUserId: me
        ).build(text: text)
    }

    public convenience init(data: DataEnvironment) {
        self.init(
            calendar: data.calendar,
            session: data.session,
            realtime: data.realtimeStatus,
            conversations: data.conversations,
            clock: data.clock
        )
    }

    /// "Send wishes" can open a chat only with a conversations repository.
    public var canSendWishes: Bool { conversations != nil }

    // MARK: Derived

    public var today: CalendarDate { CalendarDate(now, in: zone.timeZone) }
    public var selectedDate: CalendarDate { selection ?? today }
    public var scheduleZone: ScheduleZone { zone }

    public var feedKey: FeedKey {
        let date = selectedDate
        return FeedKey(
            view: view,
            anchor: date,
            interval: SchedulePeriods.fetchInterval(view, containing: date, in: zone.timeZone),
            zoneIdentifier: zone.identifier
        )
    }

    // MARK: Lifecycle

    /// Session (zone), milestones and connection status. Runs until the view's task is cancelled.
    public func start() async {
        let session = session
        let calendar = calendar
        let realtime = realtime
        await withDiscardingTaskGroup { group in
            group.addTask {
                for await state in session.states() { await self.sessionChanged(state) }
            }
            group.addTask {
                for await resource in calendar.milestones() { await self.apply(milestones: resource) }
            }
            group.addTask { await self.refreshMilestonesIfStale() }
            group.addTask {
                for await banner in realtime.banner() { await self.apply(banner: banner) }
            }
        }
    }

    /// Watches the feed for the current period and fetches it when missing or stale.
    public func observeFeed() async {
        let key = feedKey
        let calendar = calendar
        let stream = calendar.feed(period: key.view, containing: key.anchor)
        await withDiscardingTaskGroup { group in
            var checked = false
            for await resource in stream {
                guard !Task.isCancelled else { break }
                apply(feed: resource, for: key)
                if !checked {
                    checked = true
                    if needsRefresh(resource) {
                        group.addTask { await calendar.refresh(period: key.view, containing: key.anchor) }
                    }
                }
            }
        }
    }

    // MARK: Actions

    /// Switching views keeps the selected date.
    public func select(view newView: CalendarPeriod) {
        guard newView != view else { return }
        view = newView
        rebuild()
    }

    public func select(date: CalendarDate) {
        selection = date
        rebuild()
    }

    /// Previous (-1) or next (+1) period.
    public func step(_ direction: Int) {
        selection = SchedulePeriods.step(view, from: selectedDate, by: direction)
        rebuild()
    }

    /// "Today": the current date in the employee's saved zone.
    public func goToToday() {
        now = clock.now
        selection = nil
        rebuild()
    }

    /// The screen became active again, so "today" moves on after midnight or a long pause.
    public func resume() {
        now = clock.now
        rebuild()
    }

    /// Pull to refresh: feed and milestones together.
    public func refresh() async {
        let key = feedKey
        let calendar = calendar
        async let feed: Void = calendar.refresh(period: key.view, containing: key.anchor)
        async let milestones: Void = calendar.refreshMilestones()
        _ = await (feed, milestones)
    }

    /// The error state's and the banners' Retry. The model owns the task; a new tap replaces it.
    public func retry() {
        refreshTask?.cancel()
        refreshTask = Task { await self.refresh() }
    }

    public func retryMilestones() {
        refreshTask?.cancel()
        let calendar = calendar
        refreshTask = Task { await calendar.refreshMilestones() }
    }

    /// "Send wishes" on a celebration card: opens (or creates) the direct chat. The button is
    /// busy from the tap until the chat opens or fails; a second tap meanwhile is ignored.
    public func sendWishes(to userId: String) {
        guard let conversations, openingWishesFor == nil, userId != myUserId else { return }
        openingWishesFor = userId
        wishesFailure = nil
        rebuild()
        wishesTask = Task {
            let result: Result<Int, WaiveraError>
            do {
                result = .success(try await conversations.openDirectConversation(with: userId).id)
            } catch {
                result = .failure(WaiveraError.from(error))
            }
            guard !Task.isCancelled else { return }
            self.finishWishes(userId: userId, result: result)
        }
    }

    /// The view navigated to `request`; it is not offered again.
    public func wishesHandled(_ request: WishesRequest) {
        if wishesRequest == request { wishesRequest = nil }
    }

    public func dismissWishesFailure() {
        wishesFailure = nil
    }

    private func finishWishes(userId: String, result: Result<Int, WaiveraError>) {
        openingWishesFor = nil
        requestCount += 1
        switch result {
        case .success(let id): wishesRequest = WishesRequest(id: requestCount, conversationId: id)
        case .failure: wishesFailure = WishesFailure(id: requestCount, userId: userId)
        }
        rebuild()
    }

    // MARK: Inputs

    private func sessionChanged(_ state: SessionState) {
        if state.user?.id != myUserId {
            myUserId = state.user?.id
            rebuild()
        }
        let resolved = ScheduleZone.resolve(savedIdentifier: state.user?.timeZoneIdentifier)
        guard resolved != zone else { return }
        zone = resolved
        text = ScheduleText(zone: resolved.timeZone, locale: locale)
        rebuild()
    }

    private func apply(feed resource: Resource<CalendarFeed>, for key: FeedKey) {
        guard key == feedKey else { return }
        feedSnapshot = (key, resource)
        rebuild()
    }

    private func apply(milestones resource: Resource<MilestoneIndex>) {
        let previous = milestoneResource.value
        milestoneResource = resource
        if let index = resource.value, index != previous {
            milestoneCalendar = MilestoneCalendar(index)
        }
        rebuild()
    }

    private func apply(banner: ConnectionBanner) {
        let offline = banner == .offline
        guard offline != isOffline else { return }
        isOffline = offline
        rebuild()
    }

    private func refreshMilestonesIfStale() async {
        var replay = calendar.milestones().makeAsyncIterator()
        let current = await replay.next()
        if let updated = current?.updatedAt, clock.now.timeIntervalSince(updated) < Self.milestonesStaleAfter,
            current?.value != nil
        {
            return
        }
        if current?.phase == .loading { return }
        await calendar.refreshMilestones()
    }

    private func needsRefresh(_ resource: Resource<CalendarFeed>) -> Bool {
        if resource.phase == .loading { return false }
        guard resource.value != nil, let updated = resource.updatedAt else { return true }
        return clock.now.timeIntervalSince(updated) > Self.feedStaleAfter
    }

    private func rebuild() {
        let key = feedKey
        let feed = feedSnapshot.flatMap { $0.key == key ? $0.resource : nil }
        let previous = state
        var next = ScheduleStateBuilder(
            view: view,
            selectedDate: selectedDate,
            today: today,
            zone: zone,
            deviceZone: deviceZone(),
            feed: feed,
            milestones: milestoneCalendar,
            milestonesFailed: milestoneResource.error != nil,
            isOffline: isOffline,
            now: now,
            myUserId: myUserId,
            openingWishesFor: openingWishesFor
        ).build(text: text)
        // A rebuild that keeps the period (a feed update, a tick) keeps the last direction, so a
        // slide already under way is not turned around.
        next.periodStep =
            next.period == previous.period ? previous.periodStep : next.period.stepDirection(from: previous.period)
        state = next
    }
}

/// A chat opened from "Send wishes"; `id` tells two requests for the same chat apart.
public struct WishesRequest: Sendable, Hashable {
    public let id: Int
    public let conversationId: Int
}

/// "Send wishes" failed for `userId`; Retry sends it again.
public struct WishesFailure: Sendable, Hashable {
    public let id: Int
    public let userId: String
}
