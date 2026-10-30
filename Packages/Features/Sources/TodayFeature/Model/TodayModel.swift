import Foundation
import Observation
import WaiveraAPI
import WaiveraData

/// Where a Today row leads. The view turns each case into the router closure it was given.
enum TodayDestination: Hashable, Sendable {
    case chat(ChatDestination)
    case event(id: String)
    case schedule
    case activity
}

/// Today: one prioritised list rendered from the repositories' cached values first, then
/// refreshed. Every write is optimistic and put back on failure; nothing blocks on the network.
@MainActor
@Observable
final class TodayModel {
    /// How fresh each source must be to skip the refresh when the screen opens.
    static let chatsFreshFor: TimeInterval = 60
    static let activityFreshFor: TimeInterval = 30
    static let scheduleFreshFor: TimeInterval = 60
    static let milestonesFreshFor: TimeInterval = 15 * 60
    /// Relative labels ("in 25 min", "5m") are recomputed this often (02 §4 fix: they never freeze).
    static let tickInterval: Duration = .seconds(30)

    private(set) var state = TodayState()
    let feedback = TodayFeedback()

    @ObservationIgnored private let environment: DataEnvironment
    @ObservationIgnored private let clock: any WaiveraClock
    @ObservationIgnored private let uptime: () -> TimeInterval
    @ObservationIgnored private let tasks = TaskBag()
    @ObservationIgnored private let activity: ActivityController
    @ObservationIgnored private var sources = TodaySources()
    @ObservationIgnored private var local = TodayLocalState()
    @ObservationIgnored private var now: Date
    @ObservationIgnored private var connection: ConnectionBanner = .hidden
    @ObservationIgnored private var navigation = NavigationGuard()
    @ObservationIgnored private var scheduleAnchors: [CalendarDate] = []
    @ObservationIgnored private var scheduleTask: Task<Void, Never>?
    @ObservationIgnored private var failingSources: Set<String> = []
    @ObservationIgnored private let handledStore: any HandledTallyStore
    @ObservationIgnored private var handled: HandledTally?
    @ObservationIgnored private var user: CurrentUser?

    init(
        environment: DataEnvironment,
        clock: any WaiveraClock,
        uptime: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
        handledStore: any HandledTallyStore = KeyValueHandledTallyStore(store: UserDefaultsKeyValueStore())
    ) {
        self.environment = environment
        self.clock = clock
        self.uptime = uptime
        self.handledStore = handledStore
        handled = handledStore.load()
        user = environment.session.currentState.user
        now = clock.now
        activity = ActivityController(repository: environment.activity, feedback: feedback, tasks: tasks)
        activity.onChange = { [weak self] in self?.rebuild() }
        rebuild()
    }

    /// Runs while the screen is visible (`.task`): follows every source, ticks the clock and
    /// refreshes whatever is stale. Cancelling the task stops all of it.
    func run() async {
        now = clock.now
        startSchedule()
        defer {
            scheduleTask?.cancel()
            scheduleTask = nil
        }
        await withDiscardingTaskGroup { group in
            group.addTask { await self.observeConversations() }
            group.addTask { await self.observeFailedSends() }
            group.addTask { await self.activity.observe() }
            group.addTask { await self.observeMilestones() }
            group.addTask { await self.observeConnection() }
            group.addTask { await self.observeSession() }
            group.addTask { await self.tick() }
            group.addTask { await self.refreshStaleSources() }
        }
    }

    // MARK: Actions

    /// Pull to refresh: every source at once. Failures keep the cached content and show a toast.
    func refresh() async {
        guard !local.isRefreshing else { return }
        local.isRefreshing = true
        rebuild()
        let conversations = environment.conversations
        let calendar = environment.calendar
        async let chats: Void = conversations.refresh()
        async let feed = activity.refresh()
        async let weeks: Void = refreshSchedule()
        async let milestones: Void = calendar.refreshMilestones()
        _ = await (chats, feed, weeks, milestones)
        sources.conversations = await latest(conversations.conversations()) ?? sources.conversations
        local.isRefreshing = false
        rebuild()
    }

    func toggleNeedsYouExpanded() {
        local.needsYouExpanded.toggle()
        rebuild()
    }

    func setFilter(_ filter: ActivityFilter) { activity.setFilter(filter) }
    func toggleUnreadOnly() { activity.toggleUnreadOnly() }
    func clearActivityFilters() { activity.clearFilters() }
    func markRead(_ activityId: Int64) { activity.markRead(activityId) }
    func markAllRead() { activity.markAllRead() }
    func loadMoreActivity() { activity.loadMoreIfPossible() }
    func retryMoreActivity() { activity.retryMore() }

    /// Accept or Decline from Needs you. The row leaves at once and comes back if the call fails.
    func respond(toEventId eventId: String, accept: Bool) {
        local.answeredInvitations.insert(eventId)
        rebuild()
        let calendar = environment.calendar
        tasks.run { [weak self] in
            do {
                try await calendar.respond(toEventId: eventId, accept: accept)
                self?.feedback.succeed(.invitationAnswered(accept: accept))
                await self?.refreshSchedule()
            } catch {
                guard let self else { return }
                local.answeredInvitations.remove(eventId)
                rebuild()
                feedback.fail(.invitationFailed(eventId: eventId, accept: accept))
            }
        }
    }

    /// The toast's Retry.
    func retry(_ toast: TodayToast) {
        feedback.dismiss(toast.id)
        switch toast.notice {
        case .refreshFailed: tasks.run { [weak self] in await self?.refresh() }
        case .markReadFailed(let id): activity.markRead(id)
        case .markAllFailed: activity.markAllRead()
        case .invitationFailed(let eventId, let accept): respond(toEventId: eventId, accept: accept)
        case .invitationAnswered: break
        }
    }

    /// Whether to follow a tap: drops a second navigation within 600 ms. Opening an activity or
    /// a pinned mention also marks it read.
    func navigate(to destination: TodayDestination, markingRead activityId: Int64? = nil) -> TodayDestination? {
        guard navigation.allows(at: uptime()) else { return nil }
        if let activityId { activity.markRead(activityId) }
        return destination
    }

    // MARK: Sources

    private func observeConversations() async {
        for await value in environment.conversations.conversations() {
            sources.conversations = value
            rebuild()
        }
    }

    /// The outbox's failed sends, for the Not sent rows and the hero's "not sent" count.
    private func observeFailedSends() async {
        for await value in environment.conversations.failedSends() where value != sources.failedSends {
            sources.failedSends = value
            rebuild()
        }
    }

    private func observeMilestones() async {
        for await value in environment.calendar.milestones() {
            sources.milestones = value
            rebuild()
        }
    }

    /// Who is signed in, for the greeting, the hero bar and the handled tally.
    private func observeSession() async {
        for await session in environment.session.states() {
            guard let signedIn = session.user, signedIn != user else { continue }
            user = signedIn
            rebuild()
        }
    }

    /// Only for the offline line: chats, activity and the calendar resync themselves after a
    /// reconnect (data layer).
    private func observeConnection() async {
        for await banner in environment.realtimeStatus.banner() {
            connection = banner
            rebuild()
        }
    }

    /// Ticks every 30 s; when the employee's date changes, the observed weeks move with it.
    private func tick() async {
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: Self.tickInterval)
            } catch {
                return
            }
            let previousDay = today
            now = clock.now
            if today != previousDay {
                startSchedule()
                tasks.run { [weak self] in await self?.refreshSchedule() }
            }
            rebuild()
        }
    }

    /// On open, refresh only what is older than its freshness window.
    private func refreshStaleSources() async {
        let conversations = environment.conversations
        let calendar = environment.calendar
        let chats = await latest(conversations.conversations())
        let milestones = await latest(calendar.milestones())
        await withDiscardingTaskGroup { group in
            if isStale(chats?.updatedAt, freshFor: Self.chatsFreshFor) {
                group.addTask { await conversations.refresh() }
            }
            if isStale(activity.updatedAt, freshFor: Self.activityFreshFor) {
                group.addTask { await self.activity.refresh() }
            }
            if isStale(milestones?.updatedAt, freshFor: Self.milestonesFreshFor) {
                group.addTask { await calendar.refreshMilestones() }
            }
            for anchor in scheduleAnchors {
                let week = await latest(calendar.feed(period: .week, containing: anchor))
                if isStale(week?.updatedAt, freshFor: Self.scheduleFreshFor) {
                    group.addTask { await calendar.refresh(period: .week, containing: anchor) }
                }
            }
        }
    }

    private func isStale(_ updatedAt: Date?, freshFor: TimeInterval) -> Bool {
        guard let updatedAt else { return true }
        return clock.now.timeIntervalSince(updatedAt) >= freshFor
    }

    /// Follows this week and the next in the employee's zone.
    private func startSchedule() {
        scheduleTask?.cancel()
        let anchors = ScheduleRules.weekAnchors(today: today)
        scheduleAnchors = anchors
        sources.schedule = anchors.map { _ in Resource() }
        let calendar = environment.calendar
        scheduleTask = Task {
            await withDiscardingTaskGroup { group in
                for anchor in anchors {
                    group.addTask {
                        for await value in calendar.feed(period: .week, containing: anchor) {
                            await self.setWeek(value, anchor: anchor)
                        }
                    }
                }
            }
        }
        rebuild()
    }

    private func setWeek(_ value: Resource<CalendarFeed>, anchor: CalendarDate) {
        guard let index = scheduleAnchors.firstIndex(of: anchor) else { return }
        sources.schedule[index] = value
        rebuild()
    }

    private func refreshSchedule() async {
        let calendar = environment.calendar
        let anchors = scheduleAnchors
        await withDiscardingTaskGroup { group in
            for anchor in anchors {
                group.addTask { await calendar.refresh(period: .week, containing: anchor) }
            }
        }
    }

    // MARK: State

    private var zone: (zone: TimeZone, isFallback: Bool) { environment.calendar.scheduleTimeZone() }
    private var today: CalendarDate { CalendarDate(now, in: zone.zone) }

    private func rebuild() {
        var current = sources
        current.activity = activity.resource
        let zone = zone
        let context = TodayContext(
            accountName: user.map(Self.accountName) ?? "",
            myUserId: user?.id,
            firstName: GreetingRules.firstName(user?.firstName, displayName: user?.displayName),
            handled: handled,
            zone: zone.zone,
            usesFallbackTimeZone: zone.isFallback,
            now: now,
            connection: connection,
            local: local,
            activity: activity.local
        )
        let next = TodayAssembler.assemble(current, context: context)
        record(next.handledObservation)
        if next != state { state = next }
        noticeFailures(current)
    }

    /// Saves the tally as the ring already shows it (`HandledRules.progress` worked it out from
    /// the same observation), so the ring and the store never disagree.
    private func record(_ observation: HandledObservation?) {
        guard let observation else { return }
        let advanced = HandledToday.advance(handled, observation)
        guard advanced != handled else { return }
        handled = advanced
        handledStore.save(advanced)
    }

    private static func accountName(_ user: CurrentUser) -> String {
        let full = [user.firstName, user.lastName].compactMap { $0?.trimmedNonEmpty }.joined(separator: " ")
        return user.displayName?.trimmedNonEmpty ?? full.trimmedNonEmpty ?? user.email ?? ""
    }

    /// A refresh that failed while cached content is on screen gets one quiet toast; the cached
    /// content stays. Offline already says so in the quiet line.
    private func noticeFailures(_ current: TodaySources) {
        var failing = Set<String>()
        if current.conversations.error != nil, current.conversations.value?.isEmpty == false { failing.insert("chats") }
        if current.activity.error != nil, current.activity.value?.items.isEmpty == false { failing.insert("activity") }
        for (index, week) in current.schedule.enumerated() where week.error != nil && week.value?.isEmpty == false {
            failing.insert("week-\(index)")
        }
        let newlyFailing = failing.subtracting(failingSources)
        failingSources = failing
        if !newlyFailing.isEmpty, connection != .offline {
            feedback.show(.refreshFailed)
        }
    }
}
