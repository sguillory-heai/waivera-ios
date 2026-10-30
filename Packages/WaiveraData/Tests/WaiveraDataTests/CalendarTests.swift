import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures

@testable import WaiveraData

/// America/Chicago in 2026: DST starts 8 March (02:00 CST → 03:00 CDT) and ends 1 November
/// (02:00 CDT → 01:00 CST).
@Suite("Calendar time zones")
struct CalendarTimeZoneTests {
    private func event(_ id: String, _ start: Date, _ end: Date) -> CalendarEvent {
        CalendarEvent(id: id, title: id, start: start, end: end)
    }

    @Test func fallBackDayIsTwentyFiveHours() {
        #expect(date(2026, 11, 1).interval(in: chicago).duration == 25 * 3_600)
        #expect(date(2026, 3, 8).interval(in: chicago).duration == 23 * 3_600)
        #expect(date(2026, 11, 2).interval(in: chicago).duration == 24 * 3_600)
    }

    @Test func eventInsideTheRepeatedHourStaysOnItsDay() {
        // 00:30 CDT to 01:30 CST: crosses the fall-back hour, stays on 1 November.
        let crossing = event("dst", utc(2026, 11, 1, 5, 30), utc(2026, 11, 1, 7, 30))
        #expect(crossing.occurs(on: date(2026, 11, 1), in: chicago))
        #expect(!crossing.occurs(on: date(2026, 10, 31), in: chicago))
        #expect(!crossing.occurs(on: date(2026, 11, 2), in: chicago))
    }

    @Test func eventEndingAtMidnightDoesNotSpill() {
        // 23:00 to 00:00 CST on 1 November: midnight is 06:00Z after fall-back, not 05:00Z.
        let late = event("late", utc(2026, 11, 2, 5), utc(2026, 11, 2, 6))
        #expect(late.occurs(on: date(2026, 11, 1), in: chicago))
        #expect(!late.occurs(on: date(2026, 11, 2), in: chicago))
    }

    @Test func overnightEventAcrossTheTransitionShowsOnBothDays() {
        let overnight = event("night", utc(2026, 11, 1, 4), utc(2026, 11, 1, 6))
        #expect(overnight.occurs(on: date(2026, 10, 31), in: chicago))
        #expect(overnight.occurs(on: date(2026, 11, 1), in: chicago))
    }

    @Test func employeeZoneNotDeviceZoneDecidesTheDay() {
        // 23:30 CDT on 31 October is already 1 November in UTC.
        let evening = event("evening", utc(2026, 11, 1, 4, 30), utc(2026, 11, 1, 4, 45))
        #expect(evening.occurs(on: date(2026, 10, 31), in: chicago))
        #expect(evening.occurs(on: date(2026, 11, 1), in: utcZone))
    }

    @Test func springForwardEvent() {
        // 01:30 CST to 03:30 CDT is one real hour.
        let spring = event("spring", utc(2026, 3, 8, 7, 30), utc(2026, 3, 8, 8, 30))
        #expect(spring.occurs(on: date(2026, 3, 8), in: chicago))
        #expect(!spring.occurs(on: date(2026, 3, 7), in: chicago))
    }

    @Test func allDaySpansIgnoreZones() {
        var training = event("allday", utc(2026, 11, 5), utc(2026, 11, 6))
        training.allDay = .init(
            start: date(2026, 11, 5),
            endExclusive: date(2026, 11, 7),
            cancelledDates: [date(2026, 11, 6)]
        )
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? utcZone
        for zone in [chicago, tokyo, utcZone] {
            #expect(training.occurs(on: date(2026, 11, 5), in: zone))
            #expect(!training.occurs(on: date(2026, 11, 6), in: zone))
            #expect(!training.occurs(on: date(2026, 11, 7), in: zone))
        }
    }

    @Test func monthGridAcrossFallBack() {
        let dates = CalendarPeriod.month.dates(containing: date(2026, 11, 15))
        #expect(dates.count == 42)
        #expect(dates.first == date(2026, 11, 1))
        let interval = CalendarPeriod.month.fetchInterval(containing: date(2026, 11, 15), in: chicago)
        #expect(interval.start == utc(2026, 11, 1, 5))
        #expect(interval.duration == 42 * 86_400 + 3_600)
    }

    @Test func monthGridAcrossSpringForward() {
        let interval = CalendarPeriod.month.fetchInterval(containing: date(2026, 3, 10), in: chicago)
        #expect(interval.start == utc(2026, 3, 1, 6))
        #expect(interval.duration == 42 * 86_400 - 3_600)
    }

    @Test func weekAndDayPeriods() {
        #expect(CalendarPeriod.week.dates(containing: date(2026, 11, 4)).first == date(2026, 11, 1))
        #expect(CalendarPeriod.day.fetchInterval(containing: date(2026, 11, 1), in: chicago).duration == 25 * 3_600)
        #expect(CalendarPeriod.month.step(date(2026, 1, 31), by: 1) == date(2026, 2, 1))
    }

    @Test func milestonesOnTheTransitionDateAndLeapDays() {
        let birthday = Milestone(kind: .birthday, userId: "u1", displayName: "A", month: 11, day: 1)
        #expect(birthday.falls(on: date(2026, 11, 1)))
        let leap = Milestone(kind: .birthday, userId: "u2", displayName: "B", month: 2, day: 29)
        #expect(leap.falls(on: date(2027, 2, 28)))
        #expect(leap.falls(on: date(2028, 2, 29)))
        #expect(!leap.falls(on: date(2028, 2, 28)))
        let anniversary = Milestone(
            kind: .workAnniversary,
            userId: "u1",
            displayName: "A",
            month: 11,
            day: 1,
            startYear: 2026
        )
        #expect(!anniversary.falls(on: date(2026, 11, 1)))
        #expect(anniversary.years(on: date(2027, 11, 1)) == 1)
        let index = MilestoneIndex([birthday, anniversary])
        #expect(index.celebration(for: "u1", on: date(2027, 11, 1))?.kind == .both)
    }

    @Test func zonelessServerTimesAreUTC() throws {
        let feed = CalendarMapper(viewerId: viewerId).feed(
            try decodeFixture(ApiResponse<CalendarFeedResponseDto>.self, "rest-calendar-get-all-event").data
                ?? CalendarFeedResponseDto(events: [], timeOff: [], holidays: [])
        )
        let checkIn = try #require(feed.events.first { $0.id == "evt_8f2b19c4" })
        #expect(checkIn.start == utc(2026, 10, 20, 15))
        #expect(checkIn.occurs(on: date(2026, 10, 20), in: chicago))
    }
}

@Suite("Calendar repository")
struct CalendarRepositoryTests {
    private let feedRoute = "GET api/CalendarEvent/GetAllEvent"

    private func repository(
        user: CurrentUser? = alex,
        clock: TestClock = TestClock()
    ) -> (LiveCalendarRepository, RoutingTransport) {
        let transport = RoutingTransport()
        let api = APIClient(baseURL: testBaseURL, transport: transport, tokens: FakeAuth())
        let repository = LiveCalendarRepository(
            api: api,
            context: SessionContext(user: user),
            store: InMemoryLocalStore(),
            clock: clock,
            handoff: WebCallHandoff(webBaseURL: URL(string: "https://web.example.test"), api: api)
        )
        return (repository, transport)
    }

    @Test func invitationStatesFollowTheAPI() async throws {
        let (repository, transport) = repository()
        await transport.set(feedRoute, .fixture("rest-calendar-get-all-event"))
        let week = date(2026, 10, 20)
        await repository.refresh(period: .month, containing: week)
        let resource = try #require(await latest(repository.feed(period: .month, containing: week)))
        #expect(resource.phase == .loaded)
        let events = resource.value?.events ?? []
        #expect(events.first { $0.id == "evt_8f2b19c4" }?.viewerResponse == .accepted)
        // No attendee row and a null acceptance: not invited, never "pending".
        #expect(events.first { $0.id == "evt_allday_31" }?.viewerResponse == .notInvited)
        #expect(events.first { $0.id == "evt_allday_31" }?.allDay?.start == date(2026, 11, 5))
        #expect(resource.value?.holidays.first?.occurs(on: date(2026, 11, 26)) == true)
    }

    private func mappedResponse(_ extra: String) throws -> InvitationState? {
        let json = #"{"id":"e1","startTime":"2026-11-01T15:00:00Z","endTime":"2026-11-01T16:00:00Z","# + extra + "}"
        let dto = try WaiveraJSON.decoder().decode(CalendarEventResponseDto.self, from: Data(json.utf8))
        return CalendarMapper(viewerId: viewerId).event(dto).viewerResponse
    }

    @Test func pendingOnlyWhenTheAttendeeRowSaysInvited() throws {
        let invited =
            #""attendees":[{"attendeeId":"a1","type":"EMPLOYEE","ref":"usr_alex_rivera","inviteStatus":"INVITED"}]"#
        #expect(try mappedResponse(invited) == .pending)
        #expect(try mappedResponse(#""attendees":[],"isInvitationAccept":false"#) == .declined)
        #expect(try mappedResponse(#""attendees":[],"isInvitationAccept":true"#) == .accepted)
        #expect(try mappedResponse(#""attendees":[],"isInvitationAccept":null"#) == .notInvited)
    }

    @Test func emptyAndErrorStates() async throws {
        let (repository, transport) = repository()
        await transport.enqueue(feedRoute, .json(#"{"data":{"events":[],"timeOff":[],"holidays":[]}}"#), .status(500))
        await repository.refresh(period: .day, containing: date(2026, 11, 1))
        var resource = try #require(await latest(repository.feed(period: .day, containing: date(2026, 11, 1))))
        #expect(resource.value?.isEmpty == true)
        await repository.refresh(period: .day, containing: date(2026, 11, 1))
        resource = try #require(await latest(repository.feed(period: .day, containing: date(2026, 11, 1))))
        #expect(resource.error == .server(statusCode: 500))
        #expect(resource.value != nil)
    }

    @Test func fetchUsesTheEmployeeZoneRange() async throws {
        let (repository, transport) = repository()
        await transport.set(feedRoute, .fixture("rest-calendar-get-all-event"))
        await repository.refresh(period: .day, containing: date(2026, 11, 1))
        let query = await transport.requests.first?.url?.query ?? ""
        #expect(query.contains("2026-11-01T05:00:00"))
        #expect(query.contains("2026-11-02T06:00:00"))
    }

    @Test func todayIsInTheEmployeeZone() {
        let (repository, _) = repository(clock: TestClock(utc(2026, 11, 1, 4, 30)))
        #expect(repository.today() == date(2026, 10, 31))
        #expect(repository.scheduleTimeZone().isFallback == false)
    }

    @Test func respondingUpdatesEveryLoadedRange() async throws {
        let (repository, transport) = repository()
        await transport.set(feedRoute, .fixture("rest-calendar-get-all-event"))
        await transport.set("POST api/invitation/AcceptDenyMeeting", .fixture("rest-invitation-accept-deny-meeting"))
        await repository.refresh(period: .week, containing: date(2026, 10, 20))
        await repository.refresh(period: .month, containing: date(2026, 10, 20))
        try await repository.respond(toEventId: "evt_8f2b19c4", accept: false)
        for period in [CalendarPeriod.week, .month] {
            let feed = await latest(repository.feed(period: period, containing: date(2026, 10, 20)))
            #expect(feed?.value?.events.first { $0.id == "evt_8f2b19c4" }?.viewerResponse == .declined)
        }
    }

    @Test func milestonesLoad() async throws {
        let (repository, transport) = repository()
        await transport.set("GET api/CalendarEvent/milestones", .fixture("rest-calendar-get-milestones"))
        await repository.refreshMilestones()
        let index = try #require(await latest(repository.milestones())?.value)
        #expect(index.celebrations(on: date(2026, 11, 2)).map(\.userId) == ["usr_priya_raman"])
        #expect(index.celebration(for: viewerId, on: date(2027, 3, 4))?.anniversaryYears == 3)
    }
}
