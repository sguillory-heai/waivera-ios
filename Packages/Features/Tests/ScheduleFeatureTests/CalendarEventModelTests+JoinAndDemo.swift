import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ScheduleFeature

/// Answer availability, join, Message organizer, milestones and the demo environment.
@MainActor
extension CalendarEventModelTests {
    @Test func organizerHasNoAnswerButtons() async {
        let h = harness(events: [
            invitation {
                $0.ownerId = "usr_me"; $0.isOwner = true
            }
        ])
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
        }
        #expect(details(h.model)?.invitation == nil)
        #expect(details(h.model)?.isOrganizer == true)
        #expect(details(h.model)?.canMessageOrganizer == false)
        #expect(details(h.model)?.organizer?.name == "You're the organizer")
    }

    @Test func nullAcceptanceShowsNoButtons() async {
        let h = harness(events: [
            invitation {
                $0.viewerResponse = .notInvited; $0.attendees = []
            }
        ])
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
            #expect(
                details(h.model)?.joinError == "Unable to join meeting. The web meeting experience could not be opened."
            )
        }
    }

    @Test func onlineMeetingWithoutALinkSaysSo() async {
        let h = harness(events: [
            invitation {
                $0.meetingDetails = "Dial 555-0100"; $0.location = "Room 2"
            }
        ])
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
        let h = harness(events: [
            invitation {
                $0.isSprout = true; $0.meetingDetails = nil
            }
        ])
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
        let h = harness(milestones: [
            Milestone(kind: .birthday, userId: "usr_owner", displayName: "Priya Raman", month: 11, day: 3)
        ])
        await observing(h.model) {
            #expect(await eventually { details(h.model) != nil })
            #expect(details(h.model)?.organizer?.celebration == nil)
            await h.calendar.refreshMilestones()
            #expect(await eventually { details(h.model)?.organizer?.celebration?.kind == .birthday })
        }
        #expect(
            details(h.model)?.organizer?.accessibilityLabel
                == "Organized by, Priya Raman is celebrating a birthday today."
        )
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
