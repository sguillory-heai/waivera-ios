import Foundation
import WaiveraAPI
import WaiveraData

/// Today's sources: the repositories it follows, the clock tick and the stale-on-open refresh.
extension TodayModel {
    /// How fresh each source must be to skip the refresh when the screen opens.
    static let chatsFreshFor: TimeInterval = 60
    static let activityFreshFor: TimeInterval = 30
    static let scheduleFreshFor: TimeInterval = 60
    static let milestonesFreshFor: TimeInterval = 15 * 60
    /// Relative labels ("in 25 min", "5m") are recomputed this often (02 §4 fix: they never freeze).
    static let tickInterval: Duration = .seconds(30)

    func observeConversations() async {
        for await value in environment.conversations.conversations() {
            sources.conversations = value
            rebuild()
        }
    }

    /// The outbox's failed sends, for the Not sent rows and the hero's "not sent" count.
    func observeFailedSends() async {
        for await value in environment.conversations.failedSends() where value != sources.failedSends {
            sources.failedSends = value
            rebuild()
        }
    }

    func observeMilestones() async {
        for await value in environment.calendar.milestones() {
            sources.milestones = value
            rebuild()
        }
    }

    /// Who is signed in, for the greeting, the hero bar and the handled tally.
    func observeSession() async {
        for await session in environment.session.states() {
            guard let signedIn = session.user, signedIn != user else { continue }
            user = signedIn
            rebuild()
        }
    }

    /// Only for the offline line: chats, activity and the calendar resync themselves after a
    /// reconnect (data layer).
    func observeConnection() async {
        for await banner in environment.realtimeStatus.banner() {
            connection = banner
            rebuild()
        }
    }

    /// Ticks every 30 s; when the employee's date changes, the observed weeks move with it.
    func tick() async {
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
    func refreshStaleSources() async {
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
    func startSchedule() {
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

    func refreshSchedule() async {
        let calendar = environment.calendar
        let anchors = scheduleAnchors
        await withDiscardingTaskGroup { group in
            for anchor in anchors {
                group.addTask { await calendar.refresh(period: .week, containing: anchor) }
            }
        }
    }
}
