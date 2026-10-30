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
                CalendarAttendee(
                    id: "a1",
                    kind: .employee,
                    ref: "usr_me",
                    displayName: "Alex Rivera",
                    response: .pending
                )
            ]
            configure(&event)
        }
    }

    func harness(
        id: String = "inv",
        events: [CalendarEvent]? = nil,
        milestones: [Milestone] = []
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
            deviceZone: { Zones.chicago },
            locale: english
        )
        return Harness(clock: clock, calendar: calendar, conversations: conversations, model: model)
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
        let rig = harness()
        rig.calendar.holds.update { $0 = true }
        await observing(rig.model) {
            #expect(await eventually { rig.calendar.calls.count("refreshEvent:inv") == 1 })
            #expect(rig.model.state == .loading)
            rig.calendar.release()
            #expect(await eventually { details(rig.model) != nil })
        }
        #expect(details(rig.model)?.title == "Care plan review")
        #expect(details(rig.model)?.organizer?.name == "Priya Raman")
    }

    @Test func coldIdIsFetchedOnceThroughTheSingleEventLookup() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
        }
        #expect(rig.calendar.calls.all.filter { $0.hasPrefix("refresh") } == ["refreshEvent:inv"])
    }

    @Test func cachedEventIsShownWithoutAFetch() async {
        let rig = harness()
        let cached = Resource(value: EventLookup.found(invitation()), phase: .loaded, updatedAt: now)
        rig.calendar.eventCells.cell("inv").set(cached)
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(rig.calendar.calls.count("refreshEvent") == 0)
    }

    @Test func unknownIdIsNotFoundOnceEveryRangeHasSynced() async {
        let rig = harness(id: "missing")
        await observing(rig.model) {
            #expect(await eventually { rig.model.state == .notFound })
        }
    }

    @Test func coldFailureIsAnErrorAndRetryRecovers() async {
        let rig = harness()
        rig.calendar.failure.update { $0 = .server(statusCode: 502) }
        await observing(rig.model) {
            #expect(await eventually { rig.model.state == .error(.server(statusCode: 502)) })
            rig.calendar.failure.update { $0 = nil }
            rig.model.retry()
            #expect(await eventually { details(rig.model) != nil })
        }
    }

    @Test func failedRefreshKeepsTheSavedCopyWithABanner() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            rig.calendar.failure.update { $0 = .offline }
            rig.model.retry()
            #expect(await eventually { details(rig.model)?.refreshNotice != nil })
        }
    }

    @Test func acceptShowsAtOnceAndIsSentOnlyWhenTheUndoWindowEnds() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model)?.invitation?.canChange == true })
            rig.model.respond(accept: true)
            #expect(details(rig.model)?.invitation?.response == .accepted)
            #expect(details(rig.model)?.invitationStatus == "You're going.")
            #expect(details(rig.model)?.attendees.first?.detail == "Accepted")
            #expect(rig.model.undoOffer?.message == "You accepted the invitation")
            #expect(rig.model.choiceTicks == 1)
            try? await Task.sleep(for: .milliseconds(20))
            #expect(rig.calendar.calls.count("respond") == 0)
            #expect(await eventually { rig.clock.pendingSleepers > 0 })
            rig.clock.advance(by: 11)
            #expect(await eventually { rig.calendar.calls.all.contains("respond:inv:true") })
            #expect(await eventually { rig.model.successTicks == 1 })
            #expect(await eventually { details(rig.model)?.invitation?.phase == .idle })
            #expect(details(rig.model)?.invitation?.response == .accepted)
            #expect(rig.model.undoOffer == nil)
        }
    }

    @Test func toastDismissalSendsTheAnswerRightAway() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model)?.invitation != nil })
            rig.model.respond(accept: false)
            guard let offer = rig.model.undoOffer else {
                Issue.record("no undo offer")
                return
            }
            rig.model.undoDismissed(offer)
            #expect(await eventually { rig.calendar.calls.all.contains("respond:inv:false") })
        }
    }

    @Test func undoInsideTheWindowSendsNothing() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model)?.invitation != nil })
            rig.model.respond(accept: true)
            guard let offer = rig.model.undoOffer else { return }
            rig.model.undo(offer)
            #expect(details(rig.model)?.invitation?.response == .pending)
            rig.clock.advance(by: 30)
            try? await Task.sleep(for: .milliseconds(30))
            #expect(rig.calendar.calls.count("respond") == 0)
        }
    }

    @Test func aReplacedToastCannotUndoOrCommitTheNewerChoice() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model)?.invitation != nil })
            rig.model.respond(accept: true)
            guard let first = rig.model.undoOffer else { return }
            rig.model.respond(accept: false)
            rig.model.undo(first)
            rig.model.undoDismissed(first)
            #expect(details(rig.model)?.invitation?.response == .declined)
            try? await Task.sleep(for: .milliseconds(20))
            #expect(rig.calendar.calls.count("respond") == 0)
            rig.clock.advance(by: 11)
            #expect(await eventually { rig.calendar.calls.all.contains("respond:inv:false") })
            #expect(rig.calendar.calls.count("respond:inv:true") == 0)
        }
    }

    @Test func failedSaveRollsBackAndRetrySendsTheSameAnswer() async {
        let rig = harness()
        rig.calendar.respondFailure.update { $0 = .server(statusCode: 500) }
        await observing(rig.model) {
            #expect(await eventually { details(rig.model)?.invitation != nil })
            rig.model.respond(accept: true)
            guard let offer = rig.model.undoOffer else { return }
            rig.model.undoDismissed(offer)
            #expect(await eventually { details(rig.model)?.invitationFailure != nil })
            #expect(details(rig.model)?.invitation?.response == .pending)
            #expect(details(rig.model)?.invitation?.canChange == true)
            #expect(details(rig.model)?.invitationFailure?.hasPrefix("Response not saved.") == true)
            #expect(rig.model.failureTicks == 1)
            rig.calendar.respondFailure.update { $0 = nil }
            rig.model.retryResponse()
            #expect(await eventually { rig.calendar.calls.count("respond:inv:true") == 2 })
            #expect(await eventually { details(rig.model)?.invitationFailure == nil })
        }
    }

    @Test func leavingDuringTheUndoWindowStillSendsTheAnswer() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model)?.invitation != nil })
            rig.model.respond(accept: true)
        }
        rig.model.disappear()
        #expect(await eventually { rig.calendar.calls.all.contains("respond:inv:true") })
    }
}
