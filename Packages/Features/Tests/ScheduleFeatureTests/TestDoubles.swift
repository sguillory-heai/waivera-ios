import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ScheduleFeature

// Hand-written fakes for the protocols the schedule models use, so each test steers exactly the
// state it needs (cached value, failure, slow refresh). No mocking framework.

enum Zones {
    static let chicago = zone("America/Chicago")
    static let sydney = zone("Australia/Sydney")
    static let tokyo = zone("Asia/Tokyo")
    static let utc = zone("UTC")

    static func zone(_ identifier: String) -> TimeZone {
        guard let zone = TimeZone(identifier: identifier) else { preconditionFailure("missing tzdata: \(identifier)") }
        return zone
    }
}

func day(_ year: Int, _ month: Int, _ day: Int) -> CalendarDate {
    guard let date = CalendarDate(year: year, month: month, day: day) else { preconditionFailure("bad date") }
    return date
}

func instant(_ raw: String) -> Date {
    guard let date = WaiveraInstant.parse(raw) else { preconditionFailure("bad instant \(raw)") }
    return date
}

func event(
    _ id: String,
    _ start: String,
    _ end: String,
    title: String? = nil,
    configure: (inout CalendarEvent) -> Void = { _ in }
) -> CalendarEvent {
    var value = CalendarEvent(id: id, title: title ?? id, start: instant(start), end: instant(end))
    configure(&value)
    return value
}

let english = Locale(identifier: "en_US")

/// A calendar whose feeds are steered per test. Every range is served from `server`, sliced to
/// the range like the API does; `failure` and `gate` control what a refresh does.
final class TestCalendarRepository: CalendarRepository, @unchecked Sendable {
    let zone: TimeZone
    let isFallback: Bool
    let todayValue: LockedValue<CalendarDate>
    let server: LockedValue<CalendarFeed>
    let failure = LockedValue<WaiveraError?>(nil)
    let respondFailure = LockedValue<WaiveraError?>(nil)
    let milestoneFailure = LockedValue<WaiveraError?>(nil)
    let meetingResult = LockedValue<Result<URL, WaiveraError>>(.failure(.configurationMissing))
    let milestoneCell = StateCell(Resource<MilestoneIndex>())
    let milestoneServer: LockedValue<MilestoneIndex>
    let cells = CellRegistry<DateInterval, Resource<CalendarFeed>>(initial: Resource())
    let eventCells = CellRegistry<String, Resource<EventLookup>>(initial: Resource())
    let calls = CallLog()
    /// When set, refreshes wait until `release()`.
    let held = LockedValue<[CheckedContinuation<Void, Never>]>([])
    let holds = LockedValue(false)
    let clock: any WaiveraClock

    init(
        zone: TimeZone = Zones.chicago,
        isFallback: Bool = false,
        today: CalendarDate,
        feed: CalendarFeed = CalendarFeed(),
        milestones: [Milestone] = [],
        clock: any WaiveraClock
    ) {
        self.zone = zone
        self.isFallback = isFallback
        todayValue = LockedValue(today)
        server = LockedValue(feed)
        milestoneServer = LockedValue(MilestoneIndex(milestones))
        self.clock = clock
    }

    func scheduleTimeZone() -> (zone: TimeZone, isFallback: Bool) { (zone, isFallback) }
    func today() -> CalendarDate { todayValue.get() }

    func interval(_ period: CalendarPeriod, _ date: CalendarDate) -> DateInterval {
        period.fetchInterval(containing: date, in: zone)
    }

    func feed(period: CalendarPeriod, containing date: CalendarDate) -> AsyncStream<Resource<CalendarFeed>> {
        cells.cell(interval(period, date)).stream()
    }

    func cell(_ period: CalendarPeriod, _ date: CalendarDate) -> StateCell<Resource<CalendarFeed>> {
        cells.cell(interval(period, date))
    }

    func refresh(period: CalendarPeriod, containing date: CalendarDate) async {
        let range = interval(period, date)
        calls.record("refresh:\(period.rawValue):\(CalendarDate(range.start, in: zone).isoString)")
        let cell = cells.cell(range)
        cell.update { $0.phase = .loading }
        if holds.get() {
            await withCheckedContinuation { continuation in held.update { $0.append(continuation) } }
        }
        if let failure = failure.get() {
            cell.update { $0.phase = .failed(failure) }
            return
        }
        cell.set(Resource(value: slice(server.get(), range), phase: .loaded, updatedAt: clock.now))
    }

    func event(id: String) -> AsyncStream<Resource<EventLookup>> { eventCells.cell(id).stream() }

    func refreshEvent(id: String) async {
        calls.record("refreshEvent:\(id)")
        let cell = eventCells.cell(id)
        cell.update { $0.phase = .loading }
        if holds.get() {
            await withCheckedContinuation { continuation in held.update { $0.append(continuation) } }
        }
        if let failure = failure.get() {
            cell.update { $0.phase = .failed(failure) }
            return
        }
        let lookup = server.get().events.first { $0.id == id }.map(EventLookup.found) ?? .notFound
        cell.set(Resource(value: lookup, phase: .loaded, updatedAt: clock.now))
    }

    func release() {
        let waiting = held.update { list -> [CheckedContinuation<Void, Never>] in
            defer { list.removeAll() }
            return list
        }
        waiting.forEach { $0.resume() }
    }

    func respond(toEventId eventId: String, accept: Bool) async throws {
        calls.record("respond:\(eventId):\(accept)")
        if let failure = respondFailure.get() { throw failure }
        server.update { feed in
            feed.events = feed.events.map { event in
                guard event.id == eventId else { return event }
                var updated = event
                updated.viewerResponse = accept ? .accepted : .declined
                return updated
            }
        }
    }

    func milestones() -> AsyncStream<Resource<MilestoneIndex>> { milestoneCell.stream() }

    func refreshMilestones() async {
        calls.record("milestones")
        milestoneCell.update { $0.phase = .loading }
        if let failure = milestoneFailure.get() ?? failure.get() {
            milestoneCell.update { $0.phase = .failed(failure) }
            return
        }
        milestoneCell.set(Resource(value: milestoneServer.get(), phase: .loaded, updatedAt: clock.now))
    }

    func meetingURL(for event: CalendarEvent) async throws -> URL {
        calls.record("meeting:\(event.id)")
        return try meetingResult.get().get()
    }

    private func slice(_ feed: CalendarFeed, _ range: DateInterval) -> CalendarFeed {
        let first = CalendarDate(range.start, in: zone)
        let last = CalendarDate(range.end.addingTimeInterval(-1), in: zone)
        return CalendarFeed(
            events: feed.events.filter { event in
                if let allDay = event.allDay { return allDay.start <= last && allDay.endExclusive > first }
                return event.start < range.end && event.end > range.start
            },
            timeOff: feed.timeOff.filter { $0.start < range.end && $0.end > range.start },
            holidays: feed.holidays.filter { $0.start <= last && $0.end >= first }
        )
    }
}

final class TestSession: SessionRepository {
    let cell: StateCell<SessionState>

    init(user: CurrentUser?) {
        cell = StateCell(user.map(SessionState.signedIn) ?? .signedOut(nil))
    }

    static func signedIn(id: String = "usr_me", zone: String? = "America/Chicago") -> TestSession {
        TestSession(user: CurrentUser(id: id, firebaseUid: "fb_\(id)", displayName: "Me", timeZoneIdentifier: zone))
    }

    func states() -> AsyncStream<SessionState> { cell.stream() }
    var currentState: SessionState { cell.current }
    func start() async {}
    func signIn(email: String, password: String) async throws {}
    func changePassword(current: String, new: String) async throws {}
    func sendPasswordReset(email: String) async throws {}
    func retryBootstrap() async {}
    func signOut() async {}
}

final class TestRealtime: RealtimeStatusRepository {
    let status = StateCell(RealtimeStatus(state: .connected, epoch: 1))
    let bannerCell = StateCell(ConnectionBanner.hidden)

    func banner() -> AsyncStream<ConnectionBanner> { bannerCell.stream() }
    func statuses() -> AsyncStream<RealtimeStatus> { status.stream() }
    func retryNow() async {}
}

final class TestConversations: ConversationsRepository {
    let result = LockedValue<Result<Int, WaiveraError>>(.success(42))
    let calls = CallLog()
    /// How long the open-or-create takes, to leave the screen while it is under way.
    let delay = LockedValue<Duration?>(nil)

    func conversations() -> AsyncStream<Resource<[Conversation]>> { StateCell(Resource<[Conversation]>()).stream() }
    func refresh() async {}
    func conversation(id: Int) async throws -> Conversation { throw WaiveraError.notFound }
    func typing() -> AsyncStream<[Int: [String]]> { StateCell([Int: [String]]()).stream() }
    func totalUnread() -> AsyncStream<Int> { StateCell(0).stream() }
    func openDirectConversation(with userId: String) async throws -> Conversation {
        calls.record("direct:\(userId)")
        if let delay = delay.get() { try? await Task.sleep(for: delay) }
        let id = try result.get().get()
        return Conversation(id: id, kind: .direct, viewerId: "usr_me")
    }
    func createConversation(participantIds: [String]) async throws -> Conversation { throw WaiveraError.notFound }
    func leave(conversationId: Int) async throws {}
}

/// Polls until `condition` holds; models update through async streams, so tests wait for them.
@MainActor
func eventually(
    _ message: String = "condition",
    timeout: Duration = .seconds(3),
    _ condition: @MainActor () -> Bool
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return condition()
}
