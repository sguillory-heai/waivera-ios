import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

@Suite("Quick events")
struct QuickEventTests {
    private func draft(_ date: CalendarDate, _ start: Int = 9 * 60, _ end: Int = 9 * 60 + 30) -> EventDraft {
        EventDraft(title: "  Check-in  ", date: date, startMinute: start, endMinute: end)
    }

    private func json(_ dto: CalendarEventDto) throws -> [String: JSONValue] {
        let data = try WaiveraJSON.encoder().encode(dto)
        guard case .object(let object) = try WaiveraJSON.decoder().decode(JSONValue.self, from: data) else {
            Issue.record("not an object")
            return [:]
        }
        return object
    }

    @Test("Wall times keep their clock time across both 2026 DST changes")
    func wallTimesAcrossDST() {
        let fallBack = EventPayload.build(draft(date(2026, 11, 1)), zone: chicago, ownerId: viewerId)
        // 1 November: 9 AM is after the change, so CST (UTC-6).
        #expect(fallBack.startTime == utc(2026, 11, 1, 15))
        #expect(fallBack.endTime == utc(2026, 11, 1, 15, 30))
        let springForward = EventPayload.build(draft(date(2026, 3, 8)), zone: chicago, ownerId: viewerId)
        #expect(springForward.startTime == utc(2026, 3, 8, 14))
        // The night before the fall-back change is still CDT.
        let before = EventPayload.build(draft(date(2026, 10, 31)), zone: chicago, ownerId: viewerId)
        #expect(before.startTime == utc(2026, 10, 31, 14))
        #expect(fallBack.timeZone == "America/Chicago")
        #expect(fallBack.title == "Check-in")
    }

    @Test("An all-day event spans zoned midnights of a 25-hour day plus its literal dates")
    func allDayOnTheFallBackDay() throws {
        var allDay = draft(date(2026, 11, 1))
        allDay.allDay = true
        let dto = EventPayload.build(allDay, zone: chicago, ownerId: viewerId)
        #expect(dto.startTime == utc(2026, 11, 1, 5))
        #expect(dto.endTime == utc(2026, 11, 2, 6))
        let body = try json(dto)
        #expect(body["isAllDay"] == .bool(true))
        #expect(body["allDayStart"] == .string("2026-11-01"))
        #expect(body["allDayEndExclusive"] == .string("2026-11-02"))
    }

    @Test("Video meetings say Waivera; a timed new event leaves the all-day fields out")
    func videoAndLocation() throws {
        let video = try json(EventPayload.build(draft(date(2026, 11, 3)), zone: chicago, ownerId: viewerId))
        #expect(video["location"] == .string("Waivera"))
        #expect(video["isSprout"] == .bool(false))
        #expect(video["online"] == .bool(true))
        #expect(video["time_zone"] == .string("America/Chicago"))
        #expect(video["isAllDay"] == nil)
        #expect(video["allDayStart"] == nil)
        var inPerson = draft(date(2026, 11, 3))
        inPerson.waiveraVideo = false
        inPerson.location = " North house "
        let body = EventPayload.build(inPerson, zone: chicago, ownerId: viewerId)
        #expect(body.location == "North house")
        #expect(body.isSprout)
    }

    @Test("Attendees: never the owner, no duplicates, outside guests kept on edit")
    func attendees() {
        var change = draft(date(2026, 11, 3))
        change.inviteeIds = [viewerId, "usr_jordan_lee", "usr_jordan_lee"]
        change.participantIds = ["par_1"]
        change.notifyParticipants = true
        var existing = CalendarEvent(id: "e1", title: "Old", start: utc(2026, 11, 3, 15), end: utc(2026, 11, 3, 16))
        existing.ownerId = viewerId
        existing.meetingDetails = "room-7"
        existing.allDay = CalendarEvent.AllDaySpan(start: date(2026, 11, 3), endExclusive: date(2026, 11, 4))
        existing.attendees = [
            CalendarAttendee(
                id: "a",
                kind: .external,
                ref: nil,
                displayName: nil,
                email: "guest@example.test",
                response: .pending
            ),
            CalendarAttendee(id: "b", kind: .waiverParticipant, ref: "par_1", displayName: "P", response: .pending),
            CalendarAttendee(id: "c", kind: .employee, ref: viewerId, displayName: "Me", response: .accepted),
        ]
        let dto = EventPayload.build(change, zone: chicago, ownerId: viewerId, existing: existing)
        #expect(dto.attendees.map(\.type) == ["EMPLOYEE", "WAIVER_PARTICIPANT", "EXTERNAL"])
        #expect(dto.attendees.first?.ref == "usr_jordan_lee")
        #expect(dto.attendees.last?.email == "guest@example.test")
        #expect(dto.notifyParticipants)
        #expect(dto.meetingDetails == "room-7")
        // Was all day, now timed: says so explicitly.
        #expect(dto.isAllDay == false)
        #expect(EventPayload.participants(existing) == ["par_1"])
        #expect(EventPayload.invitees(existing).isEmpty)
        change.participantIds = []
        #expect(!EventPayload.build(change, zone: chicago, ownerId: viewerId).notifyParticipants)
    }

    private func repository() -> (LiveCalendarRepository, RoutingTransport) {
        let transport = RoutingTransport()
        let api = APIClient(baseURL: testBaseURL, transport: transport, tokens: FakeAuth())
        let repository = LiveCalendarRepository(
            api: api,
            context: SessionContext(user: alex),
            store: InMemoryLocalStore(),
            clock: TestClock(),
            handoff: WebCallHandoff(webBaseURL: URL(string: "https://web.example.test"), api: api)
        )
        return (repository, transport)
    }

    @Test("The directory: participants and coworkers, never me, sorted by name")
    func directory() async throws {
        let (repository, transport) = repository()
        await transport.set(
            "GET api/CalendarEvent/attendee-options",
            .json(
                #"""
                {"success":true,"data":{"people":[
                  {"id":"usr_zed","name":"Zed Park","type":"Employee"},
                  {"id":"usr_alex_rivera","name":"Alex Rivera","type":"Employee"},
                  {"id":"par_1","name":" ","email":"amy@example.test","type":"Participant"},
                  {"id":"usr_zed","name":"Zed Park","type":"Employee"},
                  {"id":"grp_1","name":"North team","type":"Group"}
                ]}}
                """#
            )
        )
        let options = try await repository.attendeeOptions(eventId: "e1")
        #expect(options.map(\.key) == ["participant:par_1", "employee:usr_zed"])
        #expect(options.first?.name == "amy@example.test")
        let query = await transport.requests.first?.url?.query ?? ""
        #expect(query.contains("mode=edit"))
        #expect(query.contains("eventId=e1"))
    }

    @Test("Cancel drops the event from loaded ranges and its lookup; success:false is a failure")
    func cancel() async throws {
        let (repository, transport) = repository()
        let feedRoute = "GET api/CalendarEvent/GetAllEvent"
        await transport.set(
            feedRoute,
            .json(
                #"""
                {"data":{"events":[{"id":"e1","title":"Mine","startTime":"2026-11-03T15:00:00Z",
                "endTime":"2026-11-03T16:00:00Z","ownerUserID":"usr_alex_rivera","attendees":[]}],
                "timeOff":[],"holidays":[]}}
                """#
            )
        )
        let day = date(2026, 11, 3)
        await repository.refresh(period: .day, containing: day)
        await transport.enqueue("DELETE api/CalendarEvent/DeleteEvent/e1", .json(#"{"success":false}"#))
        await #expect(throws: WaiveraError.self) { try await repository.cancelEvent(id: "e1") }
        #expect(try #require(await latest(repository.feed(period: .day, containing: day))).value?.events.count == 1)
        await transport.set(feedRoute, .json(#"{"data":{"events":[],"timeOff":[],"holidays":[]}}"#))
        await transport.enqueue("DELETE api/CalendarEvent/DeleteEvent/e1", .json(#"{"success":true}"#))
        try await repository.cancelEvent(id: "e1")
        #expect(
            try #require(await latest(repository.feed(period: .day, containing: day))).value?.events.isEmpty == true
        )
        #expect(await latest(repository.event(id: "e1"))?.value == .notFound)
        let query = await transport.requests.last { $0.httpMethod == "DELETE" }?.url?.query ?? ""
        #expect(query.contains("deleteScope=single"))
    }

    @Test("Create sends the payload and refreshes the loaded ranges")
    func create() async throws {
        let (repository, transport) = repository()
        let feedRoute = "GET api/CalendarEvent/GetAllEvent"
        await transport.set(feedRoute, .json(#"{"data":{"events":[],"timeOff":[],"holidays":[]}}"#))
        await repository.refresh(period: .day, containing: date(2026, 11, 1))
        await transport.set("POST api/CalendarEvent/CreateEvent", .json(#"{"success":true,"data":"e9"}"#))
        try await repository.createEvent(draft(date(2026, 11, 1)))
        #expect(await transport.count(feedRoute) == 2)
        let body = try #require(await transport.bodies("POST api/CalendarEvent/CreateEvent").first)
        let sent = try WaiveraJSON.decoder().decode(JSONValue.self, from: body)
        #expect(sent["ownerUserID"] == .string(viewerId))
        #expect(sent["startTime"]?.stringValue?.hasPrefix("2026-11-01T15:00:00") == true)
    }
}
