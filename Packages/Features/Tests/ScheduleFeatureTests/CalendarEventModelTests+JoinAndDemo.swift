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
        let rig = harness(events: [
            invitation {
                $0.ownerId = "usr_me"; $0.isOwner = true
            }
        ])
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
        }
        #expect(details(rig.model)?.invitation == nil)
        #expect(details(rig.model)?.isOrganizer == true)
        #expect(details(rig.model)?.canMessageOrganizer == false)
        #expect(details(rig.model)?.organizer?.name == "You're the organizer")
    }

    @Test func nullAcceptanceShowsNoButtons() async {
        let rig = harness(events: [
            invitation {
                $0.viewerResponse = .notInvited; $0.attendees = []
            }
        ])
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
        }
        #expect(details(rig.model)?.invitation == nil)
        rig.model.respond(accept: true)
        #expect(rig.model.undoOffer == nil)
    }

    @Test func startedEventCannotBeAnswered() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            rig.clock.advance(by: 3_700)
            rig.model.tick()
            #expect(details(rig.model)?.invitation?.canChange == false)
            #expect(details(rig.model)?.invitationStatus?.hasPrefix("This event has started") == true)
            #expect(details(rig.model)?.join?.state == .open)
            rig.model.respond(accept: true)
            #expect(rig.model.undoOffer == nil)
        }
    }

    @Test func joinOpensTheValidatedLinkOnlyInsideTheWindow() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            #expect(details(rig.model)?.join?.state == .tooEarly)
            #expect(details(rig.model)?.joinNote == "Join opens at 9:30 AM")
            rig.model.join()
            #expect(rig.model.openRequest == nil)
            rig.clock.advance(by: 31 * 60)
            rig.model.tick()
            rig.model.join()
            #expect(rig.model.openRequest?.url.absoluteString == "https://meet.example.test/care")
            guard let request = rig.model.openRequest else { return }
            rig.model.linkHandled(request, accepted: false)
            let message = "Unable to join meeting. The web meeting experience could not be opened."
            #expect(details(rig.model)?.joinError == message)
        }
    }

    @Test func onlineMeetingWithoutALinkSaysSo() async {
        let rig = harness(events: [
            invitation {
                $0.meetingDetails = "Dial 555-0100"; $0.location = "Room 2"
            }
        ])
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            rig.clock.advance(by: 31 * 60)
            rig.model.tick()
            rig.model.join()
            #expect(rig.model.openRequest == nil)
            let message = "Unable to join meeting. This meeting does not include a join link."
            #expect(details(rig.model)?.joinError == message)
        }
    }

    @Test func sproutMeetingAsksTheApiForTheLobbyAndRejectsNonWebUrls() async {
        let rig = harness(events: [
            invitation {
                $0.isSprout = true; $0.meetingDetails = nil
            }
        ])
        rig.calendar.meetingResult.update { $0 = .success(URL(string: "https://web.example.test/lobby/r1?state=x")!) }
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            rig.clock.advance(by: 31 * 60)
            rig.model.tick()
            rig.model.join()
            #expect(await eventually { rig.model.openRequest != nil })
            #expect(rig.calendar.calls.all.contains("meeting:inv"))
            if let request = rig.model.openRequest { rig.model.linkHandled(request, accepted: true) }
            rig.calendar.meetingResult.update { $0 = .success(URL(string: "waivera-evil://lobby")!) }
            rig.model.join()
            #expect(await eventually { details(rig.model)?.joinError != nil })
            #expect(rig.model.openRequest == nil)
        }
    }

    @Test func messageOrganizerOpensTheDirectConversation() async {
        let rig = harness()
        await observing(rig.model) {
            #expect(await eventually { details(rig.model)?.canMessageOrganizer == true })
            rig.model.messageOrganizer()
            #expect(await eventually { rig.model.conversationRequest?.conversationId == 42 })
        }
        #expect(rig.conversations.calls.all == ["direct:usr_owner"])
    }

    @Test func messageOrganizerFailureIsShown() async {
        let rig = harness()
        rig.conversations.result.update { $0 = .failure(.offline) }
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            rig.model.messageOrganizer()
            #expect(await eventually { details(rig.model)?.chatError != nil })
        }
    }

    @Test func milestoneLoadedLaterBadgesTheOrganizer() async {
        let rig = harness(milestones: [
            Milestone(kind: .birthday, userId: "usr_owner", displayName: "Priya Raman", month: 11, day: 3)
        ])
        await observing(rig.model) {
            #expect(await eventually { details(rig.model) != nil })
            #expect(details(rig.model)?.organizer?.celebration == nil)
            await rig.calendar.refreshMilestones()
            #expect(await eventually { details(rig.model)?.organizer?.celebration?.kind == .birthday })
        }
        #expect(
            details(rig.model)?.organizer?.accessibilityLabel
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
