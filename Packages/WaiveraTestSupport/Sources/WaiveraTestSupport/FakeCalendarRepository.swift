import Foundation
import WaiveraAPI
import WaiveraData

/// The demo calendar in the employee's zone. Every range is served from one feed, filtered
/// to the range like the server does.
public final class FakeCalendarRepository: CalendarRepository {
    private let zone: TimeZone
    private let todayDate: CalendarDate
    private let clock: any WaiveraClock
    private let feedValue: LockedValue<CalendarFeed>
    private let cells = CellRegistry<DateInterval, Resource<CalendarFeed>>(initial: Resource())
    private let eventCells = CellRegistry<String, Resource<EventLookup>>(initial: Resource())
    public let milestoneResource: FakeResource<MilestoneIndex>
    public let controls = LockedValue(FakeControls())
    public let calls = CallLog()
    /// The web base the fake lobby links point at.
    private let lobbyBase: URL?

    public init(data: DemoData, clock: any WaiveraClock, today: CalendarDate = DemoData.today, lobbyBase: URL? = nil) {
        zone = data.user.scheduleTimeZone
        todayDate = today
        self.clock = clock
        feedValue = LockedValue(data.calendar)
        milestoneResource = FakeResource(MilestoneIndex(data.milestones), clock: clock)
        self.lobbyBase = lobbyBase
    }

    public func scheduleTimeZone() -> (zone: TimeZone, isFallback: Bool) { (zone, false) }
    public func today() -> CalendarDate { todayDate }

    public func feed(period: CalendarPeriod, containing date: CalendarDate) -> AsyncStream<Resource<CalendarFeed>> {
        cells.cell(period.fetchInterval(containing: date, in: zone)).stream()
    }

    public func refresh(period: CalendarPeriod, containing date: CalendarDate) async {
        let interval = period.fetchInterval(containing: date, in: zone)
        calls.record("refresh:\(period.rawValue):\(date.isoString)")
        let cell = cells.cell(interval)
        cell.update { $0.phase = .loading }
        let controls = controls.get()
        if controls.latency > .zero { try? await clock.sleep(for: controls.latency) }
        if let failure = controls.failure {
            cell.update { $0.phase = .failed(failure) }
            return
        }
        cell.set(
            Resource(
                value: Self.slice(feedValue.get(), to: interval, in: zone),
                phase: .loaded,
                updatedAt: clock.now
            )
        )
    }

    public func respond(toEventId eventId: String, accept: Bool) async throws {
        calls.record("respond:\(eventId):\(accept)")
        if let failure = controls.get().failure { throw failure }
        let updated = feedValue.update { feed -> CalendarFeed in
            feed.events = feed.events.map { event in
                guard event.id == eventId else { return event }
                var event = event
                event.viewerResponse = accept ? .accepted : .declined
                return event
            }
            return feed
        }
        cells.forEachCell { interval, cell in
            guard cell.current.value != nil else { return }
            cell.update { $0.value = Self.slice(updated, to: interval, in: self.zone) }
        }
        if let event = updated.events.first(where: { $0.id == eventId }) {
            eventCells.cell(eventId).update { resource in
                if resource.value != nil { resource.value = .found(event) }
            }
        }
    }

    public func event(id: String) -> AsyncStream<Resource<EventLookup>> { eventCells.cell(id).stream() }

    /// Looks the id up in the whole demo calendar, with the same controls as the feeds.
    public func refreshEvent(id: String) async {
        calls.record("refreshEvent:\(id)")
        let cell = eventCells.cell(id)
        cell.update { $0.phase = .loading }
        let controls = controls.get()
        if controls.latency > .zero { try? await clock.sleep(for: controls.latency) }
        if let failure = controls.failure {
            cell.update { $0.phase = .failed(failure) }
            return
        }
        let lookup = feedValue.get().events.first { $0.id == id }.map(EventLookup.found) ?? .notFound
        cell.set(Resource(value: lookup, phase: .loaded, updatedAt: clock.now))
    }

    public func milestones() -> AsyncStream<Resource<MilestoneIndex>> { milestoneResource.stream() }
    public func refreshMilestones() async { await milestoneResource.refresh() }

    public func meetingURL(for event: CalendarEvent) async throws -> URL {
        guard let lobbyBase else { throw WaiveraError.configurationMissing }
        return lobbyBase.appending(path: "lobby").appending(path: event.id)
    }

    static func slice(_ feed: CalendarFeed, to interval: DateInterval, in zone: TimeZone) -> CalendarFeed {
        let first = CalendarDate(interval.start, in: zone)
        let last = CalendarDate(interval.end.addingTimeInterval(-1), in: zone)
        return CalendarFeed(
            events: feed.events.filter { event in
                if let allDay = event.allDay { return allDay.start <= last && allDay.endExclusive > first }
                return event.start < interval.end && event.end > interval.start
            },
            timeOff: feed.timeOff.filter { $0.start < interval.end && $0.end > interval.start },
            holidays: feed.holidays.filter { $0.start <= last && $0.end >= first }
        )
    }
}
