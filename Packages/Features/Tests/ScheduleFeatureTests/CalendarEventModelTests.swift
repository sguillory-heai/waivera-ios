import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ScheduleFeature

@MainActor
@Suite("Calendar event model", .serialized)
struct CalendarEventModelTests {
    /// 09:00 CST on 3 Nov 2026; the invitation starts at 10:00 CST.
    let now = instant("2026-11-03T15:00:00Z")

    struct Harness {
        let clock: ManualClock
        let calendar: TestCalendarRepository
        let conversations: TestConversations
        let memory: EventRangeMemory
        let model: CalendarEventModel
    }

    func invitation(_ configure: (inout CalendarEvent) -> Void = { _ in }) -> CalendarEvent {
        event("inv", "2026-11-03T16:00:00Z", "2026-11-03T16:30:00Z", title: "Care plan review") { event in
            event.ownerId = "usr_owner"
            event.ownerName = "Priya Raman"
            event.viewerResponse = .pending
            event.isOnline = true
            event.meetingDetails = "https://meet.example.test/care"
            event.attendees = [
                CalendarAttendee(id: "a1", kind: .employee, ref: "usr_me", displayName: "Alex Rivera", response: .pending)
            ]
            configure(&event)
        }
    }

    func harness(
        id: String = "inv",
        events: [CalendarEvent]? = nil,
        milestones: [Milestone] = [],
        memory: EventRangeMemory = EventRangeMemory()
    ) -> Harness {
        let clock = ManualClock(now: now)
        let calendar = TestCalendarRepository(
            today: CalendarDate(now, in: Zones.chicago),
            feed: CalendarFeed(events: events ?? [invitation()]),
            milestones: milestones,
            clock: clock
        )
        let conversations = TestConversations()
        let model = CalendarEventModel(
            eventID: id,
            calendar: calendar,
            conversations: conversations,
            session: TestSession.signedIn(),
            clock: clock,
            memory: memory,
            deviceZone: { Zones.chicago },
            locale: english
        )
        return Harness(clock: clock, calendar: calendar, conversations: conversations, memory: memory, model: model)
    }

    func observing(_ model: CalendarEventModel, _ body: () async throws -> Void) async rethrows {
        let task = Task { await model.observe() }
        defer { task.cancel() }
        try await body()
    }

    func details(_ model: CalendarEventModel) -> EventDetailsUI? {
        if case .loaded(let details) = model.state { return details }
        return nil
    }

    @Test func loadingUntilTheFeedArrivesThenLoaded() async {
        let h = harness()
        h.calendar.holds.update { $0 = true }
        await observing(h.model) {
            #expect(await eventually { h.calendar.calls.count("refresh:month") == 3 })
            #expect(h.model.state == .loading)
            h.calendar.release()
            #expect(await eventually { details(h.model) != nil })
        }
        #expect(details(h.model)?.title == "Care plan review")
        #expect(details(h.model)?.organizer?.name == "Priya Raman")
    }

    @Test func coldIdIsLookedUpInTheMonthGridsAroundTodayInTheSavedZone() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
        }
        let refreshed = Set(h.calendar.calls.all.filter { $0.hasPrefix("refresh:") })
        #expect(refreshed == ["refresh:month:2026-11-01", "refresh:month:2026-09-27", "refresh:month:2026-11-29"])
    }

    @Test func eventSeenOnTheScheduleIsWatchedInItsOwnRange() async {
        let memory = EventRangeMemory()
        memory.remember(["inv"], view: .week, anchor: day(2026, 11, 3))
        let h = harness(memory: memory)
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
        }
        #expect(h.calendar.calls.all.filter { $0.hasPrefix("refresh:") } == ["refresh:week:2026-11-01"])
    }

    @Test func unknownIdIsNotFoundOnceEveryRangeHasSynced() async {
        let h = harness(id: "missing")
        await observing(h.model) {
            #expect(await eventually { h.model.state == .notFound })
        }
    }

    @Test func coldFailureIsAnErrorAndRetryRecovers() async {
        let h = harness()
        h.calendar.failure.update { $0 = .server(statusCode: 502) }
        await observing(h.model) {
            #expect(await eventually { h.model.state == .error(.server(statusCode: 502)) })
            h.calendar.failure.update { $0 = nil }
            h.model.retry()
            #expect(await eventually { details(h.model) != nil })
        }
    }

    @Test func failedRefreshKeepsTheSavedCopyWithABanner() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            h.calendar.failure.update { $0 = .offline }
            h.model.retry()
            #expect(await eventually { details(h.model)?.refreshNotice != nil })
        }
    }

    @Test func acceptShowsAtOnceAndIsSentOnlyWhenTheUndoWindowEnds() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model)?.invitation?.canChange == true })
            h.model.respond(accept: true)
            #expect(details(h.model)?.invitation?.response == .accepted)
            #expect(details(h.model)?.invitationStatus == "You're going.")
            #expect(details(h.model)?.attendees.first?.detail == "Accepted")
            #expect(h.model.undoOffer?.message == "You accepted the invitation")
            #expect(h.model.choiceTicks == 1)
            try? await Task.sleep(for: .milliseconds(20))
            #expect(h.calendar.calls.count("respond") == 0)
            #expect(await eventually { h.clock.pendingSleepers > 0 })
            h.clock.advance(by: 11)
            #expect(await eventually { h.calendar.calls.all.contains("respond:inv:true") })
            #expect(await eventually { h.model.successTicks == 1 })
            #expect(await eventually { details(h.model)?.invitation?.phase == .idle })
            #expect(details(h.model)?.invitation?.response == .accepted)
            #expect(h.model.undoOffer == nil)
        }
    }

    @Test func toastDismissalSendsTheAnswerRightAway() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model)?.invitation != nil })
            h.model.respond(accept: false)
            guard let offer = h.model.undoOffer else {
                Issue.record("no undo offer")
                return
            }
            h.model.undoDismissed(offer)
            #expect(await eventually { h.calendar.calls.all.contains("respond:inv:false") })
        }
    }

    @Test func undoInsideTheWindowSendsNothing() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model)?.invitation != nil })
            h.model.respond(accept: true)
            guard let offer = h.model.undoOffer else { return }
            h.model.undo(offer)
            #expect(details(h.model)?.invitation?.response == .pending)
            h.clock.advance(by: 30)
            try? await Task.sleep(for: .milliseconds(30))
            #expect(h.calendar.calls.count("respond") == 0)
        }
    }

    @Test func aReplacedToastCannotUndoOrCommitTheNewerChoice() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model)?.invitation != nil })
            h.model.respond(accept: true)
            guard let first = h.model.undoOffer else { return }
            h.model.respond(accept: false)
            h.model.undo(first)
            h.model.undoDismissed(first)
            #expect(details(h.model)?.invitation?.response == .declined)
            try? await Task.sleep(for: .milliseconds(20))
            #expect(h.calendar.calls.count("respond") == 0)
            h.clock.advance(by: 11)
            #expect(await eventually { h.calendar.calls.all.contains("respond:inv:false") })
            #expect(h.calendar.calls.count("respond:inv:true") == 0)
        }
    }

    @Test func failedSaveRollsBackAndRetrySendsTheSameAnswer() async {
        let h = harness()
        h.calendar.respondFailure.update { $0 = .server(statusCode: 500) }
        await observing(h.model) {
            #expect(await eventually { details(h.model)?.invitation != nil })
            h.model.respond(accept: true)
            guard let offer = h.model.undoOffer else { return }
            h.model.undoDismissed(offer)
            #expect(await eventually { details(h.model)?.invitationFailure != nil })
            #expect(details(h.model)?.invitation?.response == .pending)
            #expect(details(h.model)?.invitation?.canChange == true)
            #expect(details(h.model)?.invitationFailure?.hasPrefix("Response not saved.") == true)
            #expect(h.model.failureTicks == 1)
            h.calendar.respondFailure.update { $0 = nil }
            h.model.retryResponse()
            #expect(await eventually { h.calendar.calls.count("respond:inv:true") == 2 })
            #expect(await eventually { details(h.model)?.invitationFailure == nil })
        }
    }

    @Test func leavingDuringTheUndoWindowStillSendsTheAnswer() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model)?.invitation != nil })
            h.model.respond(accept: true)
        }
        h.model.disappear()
        #expect(await eventually { h.calendar.calls.all.contains("respond:inv:true") })
    }

    @Test func organizerHasNoAnswerButtons() async {
        let h = harness(events: [invitation { $0.ownerId = "usr_me"; $0.isOwner = true }])
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
        }
        #expect(details(h.model)?.invitation == nil)
        #expect(details(h.model)?.isOrganizer == true)
        #expect(details(h.model)?.canMessageOrganizer == false)
        #expect(details(h.model)?.organizer?.name == "You're the organizer")
    }

    @Test func nullAcceptanceShowsNoButtons() async {
        let h = harness(events: [invitation { $0.viewerResponse = .notInvited; $0.attendees = [] }])
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
        }
        #expect(details(h.model)?.invitation == nil)
        h.model.respond(accept: true)
        #expect(h.model.undoOffer == nil)
    }

    @Test func startedEventCannotBeAnswered() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            h.clock.advance(by: 3_700)
            h.model.tick()
            #expect(details(h.model)?.invitation?.canChange == false)
            #expect(details(h.model)?.invitationStatus?.hasPrefix("This event has started") == true)
            #expect(details(h.model)?.join?.state == .open)
            h.model.respond(accept: true)
            #expect(h.model.undoOffer == nil)
        }
    }

    @Test func joinOpensTheValidatedLinkOnlyInsideTheWindow() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            #expect(details(h.model)?.join?.state == .tooEarly)
            #expect(details(h.model)?.joinNote == "Join opens at 9:30 AM")
            h.model.join()
            #expect(h.model.openRequest == nil)
            h.clock.advance(by: 31 * 60)
            h.model.tick()
            h.model.join()
            #expect(h.model.openRequest?.url.absoluteString == "https://meet.example.test/care")
            guard let request = h.model.openRequest else { return }
            h.model.linkHandled(request, accepted: false)
            #expect(details(h.model)?.joinError == "Unable to join meeting. The web meeting experience could not be opened.")
        }
    }

    @Test func onlineMeetingWithoutALinkSaysSo() async {
        let h = harness(events: [invitation { $0.meetingDetails = "Dial 555-0100"; $0.location = "Room 2" }])
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            h.clock.advance(by: 31 * 60)
            h.model.tick()
            h.model.join()
            #expect(h.model.openRequest == nil)
            #expect(details(h.model)?.joinError == "Unable to join meeting. This meeting does not include a join link.")
        }
    }

    @Test func sproutMeetingAsksTheApiForTheLobbyAndRejectsNonWebUrls() async {
        let h = harness(events: [invitation { $0.isSprout = true; $0.meetingDetails = nil }])
        h.calendar.meetingResult.update { $0 = .success(URL(string: "https://web.example.test/lobby/r1?state=x")!) }
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            h.clock.advance(by: 31 * 60)
            h.model.tick()
            h.model.join()
            #expect(await eventually { h.model.openRequest != nil })
            #expect(h.calendar.calls.all.contains("meeting:inv"))
            if let request = h.model.openRequest { h.model.linkHandled(request, accepted: true) }
            h.calendar.meetingResult.update { $0 = .success(URL(string: "waivera-evil://lobby")!) }
            h.model.join()
            #expect(await eventually { details(h.model)?.joinError != nil })
            #expect(h.model.openRequest == nil)
        }
    }

    @Test func messageOrganizerOpensTheDirectConversation() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model)?.canMessageOrganizer == true })
            h.model.messageOrganizer()
            #expect(await eventually { h.model.conversationRequest?.conversationId == 42 })
        }
        #expect(h.conversations.calls.all == ["direct:usr_owner"])
    }

    @Test func messageOrganizerFailureIsShown() async {
        let h = harness()
        h.conversations.result.update { $0 = .failure(.offline) }
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            h.model.messageOrganizer()
            #expect(await eventually { details(h.model)?.chatError != nil })
        }
    }

    @Test func milestoneLoadedLaterBadgesTheOrganizer() async {
        let h = harness(milestones: [Milestone(kind: .birthday, userId: "usr_owner", displayName: "Priya Raman", month: 11, day: 3)])
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            #expect(details(h.model)?.organizer?.celebration == nil)
            await h.calendar.refreshMilestones()
            #expect(await eventually { details(h.model)?.organizer?.celebration?.kind == .birthday })
        }
        #expect(details(h.model)?.organizer?.accessibilityLabel == "Organized by, Priya Raman is celebrating a birthday today.")
    }

    @Test func demoFixtureEventIsFoundFromAColdLink() async {
        // The route catalog opens evt_8f2b19c4 (20 Oct) while the demo "today" is 1 Nov.
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let model = CalendarEventModel(
            eventID: "evt_8f2b19c4",
            calendar: fake.calendar,
            conversations: fake.chat,
            session: fake.session,
            clock: fake.clock,
            memory: EventRangeMemory(),
            deviceZone: { Zones.chicago },
            locale: english
        )
        await observing(model) {
            #expect(await eventually { details(model) != nil })
        }
        #expect(details(model)?.title == "North team check-in")
        #expect(details(model)?.timePrimary == "Tue, Oct 20, 10:00 AM")
        #expect(details(model)?.attendees.count == 3)
        #expect(details(model)?.attendees.last?.celebration == nil)
    }

    @Test func demoPendingInvitationCanBeAccepted() async {
        let fake = FakeDataEnvironment.make(clock: ManualClock())
        await fake.environment.launch()
        let model = CalendarEventModel(
            eventID: "evt_demo_invite",
            calendar: fake.calendar,
            conversations: fake.chat,
            session: fake.session,
            clock: fake.clock,
            memory: EventRangeMemory(),
            deviceZone: { Zones.chicago },
            locale: english
        )
        await observing(model) {
            #expect(await eventually { details(model)?.invitation?.response == .pending })
            model.respond(accept: true)
            guard let offer = model.undoOffer else { return }
            model.undoDismissed(offer)
            #expect(await eventually { fake.calendar.calls.all.contains("respond:evt_demo_invite:true") })
            #expect(await eventually { details(model)?.invitation?.phase == .idle })
            #expect(details(model)?.invitation?.response == .accepted)
        }
    }
}
