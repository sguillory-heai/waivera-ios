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
        let h = harness()
        h.calendar.holds.update { $0 = true }
        await observing(h.model) {
            #expect(await eventually { h.calendar.calls.count("refreshEvent:inv") == 1 })
            #expect(h.model.state == .loading)
            h.calendar.release()
            #expect(await eventually { details(h.model) != nil })
        }
        #expect(details(h.model)?.title == "Care plan review")
        #expect(details(h.model)?.organizer?.name == "Priya Raman")
    }

    @Test func coldIdIsFetchedOnceThroughTheSingleEventLookup() async {
        let h = harness()
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
        }
        #expect(h.calendar.calls.all.filter { $0.hasPrefix("refresh") } == ["refreshEvent:inv"])
    }

    @Test func cachedEventIsShownWithoutAFetch() async {
        let h = harness()
        let cached = Resource(value: EventLookup.found(invitation()), phase: .loaded, updatedAt: now)
        h.calendar.eventCells.cell("inv").set(cached)
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            try? await Task.sleep(for: .milliseconds(30))
        }
        #expect(h.calendar.calls.count("refreshEvent") == 0)
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
}
