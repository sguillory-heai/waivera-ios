import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ScheduleFeature

@Suite("Event rules")
struct EventRulesTests {
    let myId = "usr_me"
    let chicago = Zones.chicago

    private func invited(_ response: InvitationState = .pending, owner: String = "usr_owner") -> CalendarEvent {
        event("e", "2026-11-03T16:00:00Z", "2026-11-03T16:30:00Z") { event in
            event.ownerId = owner
            event.isOwner = owner == "usr_me"
            event.viewerResponse = response
            event.attendees = [
                CalendarAttendee(id: "a1", kind: .employee, ref: "usr_me", displayName: "Me", response: response),
                CalendarAttendee(
                    id: "a2",
                    kind: .external,
                    ref: nil,
                    displayName: nil,
                    email: "guest@example.com",
                    response: .tentative
                ),
            ]
        }
    }

    private let beforeStart = instant("2026-11-03T12:00:00Z")

    @Test func invitedAttendeeBeforeTheStartCanAcceptOrDecline() {
        let invitation = EventRules.invitation(
            invited(),
            myUserId: myId,
            now: beforeStart,
            zone: chicago,
            optimistic: nil
        )
        #expect(invitation?.response == .pending)
        #expect(invitation?.canChange == true)
    }

    @Test func ownerNeverSeesAcceptOrDecline() {
        let owned = invited(owner: myId)
        #expect(EventRules.invitation(owned, myUserId: myId, now: beforeStart, zone: chicago, optimistic: nil) == nil)
        var byId = invited(owner: myId)
        byId.isOwner = false
        #expect(EventRules.isOrganizer(byId, myUserId: myId))
    }

    @Test func startedEventHidesTheButtonsAndJoinGoverns() {
        var online = invited()
        online.isOnline = true
        online.meetingDetails = "https://meet.example.test/x"
        let during = instant("2026-11-03T16:10:00Z")
        let invitation = EventRules.invitation(
            online,
            myUserId: myId,
            now: during,
            zone: chicago,
            optimistic: nil
        )
        #expect(invitation?.canChange == false)
        #expect(EventRules.join(online, now: during, isBusy: false, error: nil)?.state == .open)
    }

    @Test func nullAcceptanceMeansNotInvitedOrUnknownNeverPending() {
        for response in [InvitationState.notInvited, .unknown, .cancelled] {
            let event = invited(response)
            #expect(
                EventRules.invitation(
                    event,
                    myUserId: myId,
                    now: beforeStart,
                    zone: chicago,
                    optimistic: nil
                ) == nil
            )
        }
        let declined = EventRules.invitation(
            invited(.declined),
            myUserId: myId,
            now: beforeStart,
            zone: chicago,
            optimistic: nil
        )
        #expect(declined?.response == .declined)
        #expect(declined?.canChange == true)
    }

    @Test func optimisticAnswerShowsAtOnceAndLocksWhileSaving() {
        let undo = EventRules.invitation(
            invited(),
            myUserId: myId,
            now: beforeStart,
            zone: chicago,
            optimistic: OptimisticResponse(accept: true, phase: .undoWindow)
        )
        #expect(undo?.response == .accepted)
        #expect(undo?.canChange == true)
        let saving = EventRules.invitation(
            invited(),
            myUserId: myId,
            now: beforeStart,
            zone: chicago,
            optimistic: OptimisticResponse(accept: false, phase: .saving)
        )
        #expect(saving?.response == .declined)
        #expect(saving?.canChange == false)
        let rows = EventRules.attendees(
            invited(),
            myUserId: myId,
            optimistic: OptimisticResponse(accept: false, phase: .saving),
            milestones: .empty,
            today: day(2026, 11, 3)
        )
        #expect(rows.first?.response == .declined)
        #expect(rows.first?.isMe == true)
    }

    @Test func joinWindowOpens30MinutesBeforeTheStartAndClosesAfterTheEnd() {
        var meeting = invited()
        meeting.isOnline = true
        meeting.meetingDetails = "https://meet.example.test/x"
        let start = meeting.start
        #expect(
            EventRules.join(meeting, now: start.addingTimeInterval(-31 * 60), isBusy: false, error: nil)?.state
                == .tooEarly
        )
        #expect(
            EventRules.join(meeting, now: start.addingTimeInterval(-29 * 60), isBusy: false, error: nil)?.state == .open
        )
        #expect(EventRules.join(meeting, now: meeting.end, isBusy: false, error: nil)?.state == .open)
        #expect(
            EventRules.join(meeting, now: meeting.end.addingTimeInterval(1), isBusy: false, error: nil)?.state == .ended
        )
        #expect(
            EventRules.join(meeting, now: start, isBusy: false, error: nil)?.opensAt == start.addingTimeInterval(-1_800)
        )
    }

    @Test func inPersonEventsWithoutALinkHaveNoJoinButton() {
        var inPerson = invited()
        inPerson.location = "North house"
        #expect(EventRules.join(inPerson, now: inPerson.start, isBusy: false, error: nil) == nil)
        inPerson.location = "https://maps.example.test/north"
        #expect(EventRules.join(inPerson, now: inPerson.start, isBusy: false, error: nil)?.state == .open)
    }

    @Test func allDayEventsHaveNoJoinTimeAndAnswerUntilTheirFirstMidnight() {
        var allDay = invited()
        allDay.isOnline = true
        allDay.allDay = .init(start: day(2026, 11, 3), endExclusive: day(2026, 11, 4))
        #expect(EventRules.join(allDay, now: beforeStart, isBusy: false, error: nil)?.state == .noTime)
        let justBefore = instant("2026-11-03T05:59:00Z")
        let justAfter = instant("2026-11-03T06:00:00Z")
        #expect(EventRules.notStarted(allDay, now: justBefore, zone: chicago))
        #expect(!EventRules.notStarted(allDay, now: justAfter, zone: chicago))
    }

    @Test func meetingLinksMustBeAbsoluteWebUrls() {
        #expect(WebLinks.isWebURL(URL(string: "https://meet.example.test/a")))
        #expect(WebLinks.isWebURL(URL(string: "HTTP://meet.example.test")))
        for bad in ["javascript:alert(1)", "ftp://files.example.test", "/relative", "https://", "mailto:a@b.c"] {
            #expect(!WebLinks.isWebURL(URL(string: bad)), "\(bad)")
        }
        var unsafe = invited()
        unsafe.meetingDetails = "javascript:alert(1)"
        unsafe.isOnline = true
        #expect(unsafe.joinURL == nil)
    }

    @Test func nonEmployeeAttendeesGetNoMilestoneBadge() {
        let milestones = MilestoneCalendar(
            MilestoneIndex([
                Milestone(kind: .birthday, userId: "usr_me", displayName: "Me", month: 11, day: 3),
                Milestone(kind: .birthday, userId: "guest@example.com", displayName: "Guest", month: 11, day: 3),
            ])
        )
        let rows = EventRules.attendees(
            invited(),
            myUserId: myId,
            optimistic: nil,
            milestones: milestones,
            today: day(2026, 11, 3)
        )
        #expect(rows[0].celebration?.kind == .birthday)
        #expect(rows[1].celebration == nil)
        #expect(rows[1].userId == nil)
    }

    @Test func messageOrganizerIsOfferedToEveryoneButTheOrganizer() {
        #expect(EventRules.canMessageOrganizer(invited(), myUserId: myId))
        #expect(!EventRules.canMessageOrganizer(invited(owner: myId), myUserId: myId))
        var ownerless = invited()
        ownerless.ownerId = nil
        #expect(!EventRules.canMessageOrganizer(ownerless, myUserId: myId))
    }

    @Test func detailsPlaceTheEventInTheSavedZone() {
        let formatter = EventDetailsFormatter(
            zone: ScheduleZone.resolve(savedIdentifier: "America/Chicago"),
            deviceZone: Zones.tokyo,
            now: beforeStart,
            myUserId: myId,
            milestones: .empty
        )
        let details = formatter.details(
            invited(),
            interaction: EventInteraction(),
            refreshFailed: false,
            text: ScheduleText(zone: Zones.chicago, locale: english)
        )
        #expect(details.timePrimary == "Tue, Nov 3, 10:00 AM")
        #expect(details.timeSecondary == "Until 10:30 AM")
        #expect(details.zoneNotice?.hasPrefix("Times shown in") == true)
        #expect(details.invitationStatus == "You haven't responded yet.")
        #expect(details.attendees.map(\.name) == ["Me (you)", "guest@example.com"])
        #expect(details.attendees.map(\.detail) == ["Awaiting response", "Maybe"])
        #expect(details.attendeeCount == "2 people")
    }
}
