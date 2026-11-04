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

    // MARK: Quick events

    /// The invite directory: two coworkers and a participant with an email on file.
    public static let directory = [
        AttendeeOption(id: "usr_jordan_lee", name: "Jordan Lee", email: "jordan@example.test"),
        AttendeeOption(id: "usr_priya_raman", name: "Priya Raman", email: "priya@example.test"),
        AttendeeOption(id: "par_morgan_hale", name: "Morgan Hale", email: "morgan@example.test", isParticipant: true),
    ]

    /// Every draft created or saved, in order.
    public let savedDrafts = LockedValue<[EventDraft]>([])

    public func attendeeOptions(eventId: String?) async throws -> [AttendeeOption] {
        calls.record("attendeeOptions:\(eventId ?? "new")")
        if let failure = controls.get().failure { throw failure }
        return Self.directory
    }

    public func createEvent(_ draft: EventDraft) async throws {
        calls.record("createEvent:\(draft.date.isoString)")
        if let failure = controls.get().failure { throw failure }
        savedDrafts.update { $0.append(draft) }
        let id = "evt_new_\(savedDrafts.get().count)"
        var event = CalendarEvent(id: id, title: draft.title, start: Date(), end: Date())
        event.ownerId = DemoData.viewerId
        event.isOwner = true
        apply(draft, to: &event)
        publish(
            feedValue.update { feed -> CalendarFeed in
                feed = CalendarFeed(events: feed.events + [event], timeOff: feed.timeOff, holidays: feed.holidays)
                return feed
            }
        )
    }

    public func updateEvent(_ event: CalendarEvent, with draft: EventDraft) async throws {
        calls.record("updateEvent:\(event.id)")
        if let failure = controls.get().failure { throw failure }
        savedDrafts.update { $0.append(draft) }
        var changed = event
        apply(draft, to: &changed)
        publish(
            feedValue.update { feed -> CalendarFeed in
                feed.events = feed.events.map { $0.id == event.id ? changed : $0 }
                return feed
            }
        )
        eventCells.cell(event.id).set(Resource(value: .found(changed), phase: .loaded, updatedAt: clock.now))
    }

    public func cancelEvent(id: String) async throws {
        calls.record("cancelEvent:\(id)")
        if let failure = controls.get().failure { throw failure }
        publish(
            feedValue.update { feed -> CalendarFeed in
                feed.events.removeAll { $0.id == id }
                return feed
            }
        )
        eventCells.cell(id).set(Resource(value: .notFound, phase: .loaded, updatedAt: clock.now))
    }

    private func apply(_ draft: EventDraft, to event: inout CalendarEvent) {
        let payload = EventPayload.build(
            draft,
            zone: zone,
            ownerId: event.ownerId ?? DemoData.viewerId,
            existing: event
        )
        event.title = payload.title
        event.start = payload.startTime
        event.end = payload.endTime
        event.allDay =
            draft.allDay ? CalendarEvent.AllDaySpan(start: draft.date, endExclusive: draft.date.adding(days: 1)) : nil
        event.details = payload.description.isEmpty ? nil : payload.description
        event.location = payload.location.isEmpty ? nil : payload.location
        event.isSprout = payload.isSprout
        event.isOnline = true
        let names = Dictionary(Self.directory.map { ($0.key, $0.name) }, uniquingKeysWith: { first, _ in first })
        let kept = event.attendees.filter { $0.kind == .external }
        let coworkers = draft.inviteeIds.map { id in
            CalendarAttendee(
                id: "att_\(id)",
                kind: .employee,
                ref: id,
                displayName: names["employee:\(id)"],
                response: .pending
            )
        }
        let participants = draft.participantIds.map { id in
            CalendarAttendee(
                id: "att_\(id)",
                kind: .waiverParticipant,
                ref: id,
                displayName: names["participant:\(id)"],
                response: .pending
            )
        }
        event.attendees = coworkers + participants + kept
    }

    private func publish(_ updated: CalendarFeed) {
        cells.forEachCell { interval, cell in
            guard cell.current.value != nil else { return }
            cell.update { $0.value = Self.slice(updated, to: interval, in: self.zone) }
        }
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
