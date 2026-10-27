import Foundation
import WaiveraAPI

/// Calendar feed per rendered grid range, milestones and invitations, all in the employee's
/// saved zone (07 §6).
public actor LiveCalendarRepository: CalendarRepository {
    private let api: APIClient
    private let context: SessionContext
    private let store: any LocalStore
    private let clock: any WaiveraClock
    private let handoff: WebCallHandoff
    private let feeds = CellRegistry<DateInterval, Resource<CalendarFeed>>(initial: Resource())
    private var loaded: [DateInterval: CalendarFeed] = [:]
    private let milestoneCell = StateCell(Resource<MilestoneIndex>())
    private var generation = 0
    private let writes = SerialQueue()

    public init(
        api: APIClient,
        context: SessionContext,
        store: any LocalStore,
        clock: any WaiveraClock,
        handoff: WebCallHandoff
    ) {
        self.api = api
        self.context = context
        self.store = store
        self.clock = clock
        self.handoff = handoff
    }

    public nonisolated func scheduleTimeZone() -> (zone: TimeZone, isDeviceFallback: Bool) {
        guard let user = context.currentUser else { return (.current, true) }
        return (user.scheduleTimeZone, user.isUsingDeviceTimeZone)
    }

    public nonisolated func today() -> CalendarDate {
        CalendarDate(clock.now, in: scheduleTimeZone().zone)
    }

    public nonisolated func feed(period: CalendarPeriod, containing date: CalendarDate)
        -> AsyncStream<Resource<CalendarFeed>>
    {
        feeds.cell(period.fetchInterval(containing: date, in: scheduleTimeZone().zone)).stream()
    }

    public func begin() async {
        guard let cached = await store.load([Milestone].self, for: .milestones) else { return }
        milestoneCell.set(Resource(value: MilestoneIndex(cached), phase: .idle))
    }

    /// Sign-out: drops state and waits for queued cache writes so none lands after the wipe.
    public func reset() async {
        generation += 1
        loaded.removeAll()
        feeds.resetAll()
        milestoneCell.set(Resource())
        await writes.drain()
    }

    public func refresh(period: CalendarPeriod, containing date: CalendarDate) async {
        guard let user = context.currentUser else { return }
        let interval = period.fetchInterval(containing: date, in: user.scheduleTimeZone)
        let cell = feeds.cell(interval)
        let current = generation
        if cell.current.value == nil, let cached = await store.load(CalendarFeed.self, for: .calendar(interval)) {
            cell.set(Resource(value: cached, phase: .loading))
        } else {
            cell.update { $0.phase = .loading }
        }
        do {
            let dto = try await api.calendarFeed(start: interval.start, end: interval.end)
            guard generation == current else { return }
            let feed = CalendarMapper(viewerId: user.id).feed(dto)
            loaded[interval] = feed
            cell.set(Resource(value: feed, phase: .loaded, updatedAt: clock.now))
            let store = store
            writes.enqueue { await store.save(feed, for: .calendar(interval)) }
        } catch {
            guard generation == current else { return }
            cell.update { $0.phase = .failed(WaiveraError.from(error)) }
        }
    }

    /// The new answer shows everywhere at once; the screen refetches its range after.
    public func respond(toEventId eventId: String, accept: Bool) async throws {
        let user = try context.requireUser()
        do {
            try await api.respondToInvitation(
                InternalInvitationResponseReq(calendarEventId: eventId, isInvitationAccept: accept, userId: user.id)
            )
        } catch {
            throw WaiveraError.from(error)
        }
        for (interval, feed) in loaded where feed.events.contains(where: { $0.id == eventId }) {
            var updated = feed
            updated.events = feed.events.map { event in
                guard event.id == eventId else { return event }
                var event = event
                event.viewerResponse = accept ? .accepted : .declined
                return event
            }
            loaded[interval] = updated
            feeds.cell(interval).update { $0.value = updated }
        }
    }

    public nonisolated func milestones() -> AsyncStream<Resource<MilestoneIndex>> { milestoneCell.stream() }

    public func refreshMilestones() async {
        let current = generation
        milestoneCell.update { $0.phase = .loading }
        do {
            let milestones = try await api.milestones().compactMap(CalendarMapper.milestone)
            guard generation == current else { return }
            milestoneCell.set(Resource(value: MilestoneIndex(milestones), phase: .loaded, updatedAt: clock.now))
            let store = store
            writes.enqueue { await store.save(milestones, for: .milestones) }
        } catch {
            guard generation == current else { return }
            milestoneCell.update { $0.phase = .failed(WaiveraError.from(error)) }
        }
    }

    public func meetingURL(for event: CalendarEvent) async throws -> URL {
        try await handoff.url(for: event)
    }
}
