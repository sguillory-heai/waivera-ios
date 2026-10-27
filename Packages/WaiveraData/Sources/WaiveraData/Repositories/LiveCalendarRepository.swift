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
    private let events = CellRegistry<String, Resource<EventLookup>>(initial: Resource())
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

    public nonisolated func scheduleTimeZone() -> (zone: TimeZone, isFallback: Bool) {
        let zone = context.currentUser?.scheduleZone ?? ScheduleZone.resolve(savedIdentifier: nil)
        return (zone.timeZone, zone.isFallback)
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
        events.resetAll()
        milestoneCell.set(Resource())
        await writes.drain()
    }

    public func refresh(period: CalendarPeriod, containing date: CalendarDate) async {
        guard let user = context.currentUser else { return }
        await refresh(interval: period.fetchInterval(containing: date, in: user.scheduleTimeZone), user: user)
    }

    /// After a reconnect: every feed that has been loaded or is on screen, plus milestones, so
    /// an invitation or change made while offline shows without a pull to refresh (05 §2).
    public func refreshObserved() async {
        guard let user = context.currentUser else { return }
        var intervals = Set(loaded.keys)
        feeds.forEachCell { interval, cell in
            if cell.current.value != nil || cell.current.phase != .idle { intervals.insert(interval) }
        }
        await withDiscardingTaskGroup { group in
            for interval in intervals {
                group.addTask { await self.refresh(interval: interval, user: user) }
            }
        }
        await refreshMilestones()
    }

    private func refresh(interval: DateInterval, user: CurrentUser) async {
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
            publishEvents(from: feed)
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
        events.cell(eventId).update { resource in
            guard case .found(var event) = resource.value else { return }
            event.viewerResponse = accept ? .accepted : .declined
            resource.value = .found(event)
        }
    }

    // MARK: Single event

    public nonisolated func event(id: String) -> AsyncStream<Resource<EventLookup>> {
        events.cell(id).stream()
    }

    /// A loaded feed's copy first. A recurring occurrence (composite id) is looked up in the
    /// month feed of its own date; a series or one-off event comes from `GetEventbyId`.
    public func refreshEvent(id: String) async {
        guard let user = context.currentUser else { return }
        let cell = events.cell(id)
        let current = generation
        if cell.current.value == nil, let cached = cachedEvent(id) {
            cell.set(Resource(value: .found(cached), phase: .loading))
        } else {
            cell.update { $0.phase = .loading }
        }
        if let occurrence = CalendarEvent.occurrenceInstant(fromId: id) {
            let zone = user.scheduleTimeZone
            let month = CalendarPeriod.month.fetchInterval(containing: CalendarDate(occurrence, in: zone), in: zone)
            await refresh(interval: month, user: user)
            guard generation == current else { return }
            let feedFailure = feeds.cell(month).current.error
            if let event = cachedEvent(id) {
                cell.set(Resource(value: .found(event), phase: .loaded, updatedAt: clock.now))
            } else if let feedFailure {
                cell.update { $0.phase = .failed(feedFailure) }
            } else {
                cell.set(Resource(value: .notFound, phase: .loaded, updatedAt: clock.now))
            }
            return
        }
        do {
            let dto = try await api.calendarEvent(id: id)
            guard generation == current else { return }
            let event = CalendarMapper(viewerId: user.id).event(dto)
            cell.set(Resource(value: .found(event), phase: .loaded, updatedAt: clock.now))
        } catch {
            guard generation == current else { return }
            let failure = WaiveraError.from(error)
            if failure == .notFound {
                cell.set(Resource(value: .notFound, phase: .loaded, updatedAt: clock.now))
            } else {
                cell.update { $0.phase = .failed(failure) }
            }
        }
    }

    private func cachedEvent(_ id: String) -> CalendarEvent? {
        for feed in loaded.values {
            if let event = feed.events.first(where: { $0.id == id }) { return event }
        }
        return nil
    }

    /// Keeps open single-event lookups in step with the newest feed that holds them.
    private func publishEvents(from feed: CalendarFeed) {
        events.forEachCell { id, cell in
            guard let event = feed.events.first(where: { $0.id == id }) else { return }
            cell.update { resource in
                resource.value = .found(event)
                if resource.updatedAt == nil { resource.updatedAt = clock.now }
            }
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
