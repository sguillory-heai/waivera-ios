import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import TodayFeature

/// Next up and celebrations in the employee's saved zone, across the DST change.
struct TodayScheduleAssemblyTests {
    private let today = Fixture.today

    private func assemble(
        _ sources: TodaySources = Fixture.sources(),
        _ context: TodayContext = Fixture.context()
    ) -> TodayState {
        TodayAssembler.assemble(sources, context: context)
    }

    // MARK: Next up

    @Test func nextUpShowsTheNextThreeAllDayFirstSkippingEndedDeclinedAndPending() {
        let events = [
            Fixture.event("ended", "2026-11-01T14:00:00Z", "2026-11-01T15:00:00Z"),
            Fixture.event("declined", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z", response: .declined),
            Fixture.event("pending", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z", response: .pending),
            Fixture.event("cancelled", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z", response: .cancelled),
            Fixture.event("visit", "2026-11-01T16:55:00Z", "2026-11-01T18:00:00Z"),
            Fixture.event("now", "2026-11-01T16:00:00Z", "2026-11-01T17:00:00Z"),
            Fixture.event("tomorrow", "2026-11-02T15:00:00Z", "2026-11-02T16:00:00Z"),
            Fixture.allDay("holiday", from: today, until: today.adding(days: 1)),
        ]
        let items = assemble(Fixture.sources(events: events)).nextUp.items
        #expect(items.map(\.eventId) == ["holiday", "now", "visit"])
        #expect(items[0].time == .allDayToday)
        #expect(items[0].start == nil)
        #expect(items[1].time == .now(until: ClockTime(hour: 11, minute: 0)))
        #expect(items[1].isHappeningNow)
        #expect(items[2].time == .inMinutes(25))
        #expect(items[2].start == ClockTime(hour: 10, minute: 55))
        #expect(items[2].isSoon)
    }

    @Test func aMultiDayAllDayItemThatStartedEarlierCountsAsToday() {
        let trip = Fixture.allDay("trip", from: today.adding(days: -2), until: today.adding(days: 2))
        #expect(assemble(Fixture.sources(events: [trip])).nextUp.items.map(\.time) == [.allDayToday])
        let past = Fixture.allDay("past", from: today.adding(days: -2), until: today)
        #expect(assemble(Fixture.sources(events: [past])).nextUp.items.isEmpty)
    }

    @Test func anOvernightShiftAcrossTheFallBackHourShowsLocalTimesAndEndsNextDay() {
        // 22:00 CDT on 31 Oct to 06:00 CST on 1 Nov (nine real hours), seen at 21:00 CDT on 31 Oct.
        let shift = Fixture.event("overnight", "2026-11-01T03:00:00Z", "2026-11-01T12:00:00Z")
        let evening = Fixture.instant("2026-11-01T02:00:00Z")
        let item = assemble(Fixture.sources(events: [shift]), Fixture.context(now: evening)).nextUp.items.first
        #expect(item?.start == ClockTime(hour: 22, minute: 0))
        #expect(item?.end == ClockTime(hour: 6, minute: 0))
        #expect(item?.endsOnLaterDay == true)
        #expect(item?.time == .inHours(1, minutes: 0))
    }

    @Test func anItemEndingExactlyAtMidnightDoesNotEndOnALaterDay() {
        let late = Fixture.event("late", "2026-11-02T04:00:00Z", "2026-11-02T06:00:00Z")  // 22:00 to 00:00 CST
        #expect(assemble(Fixture.sources(events: [late])).nextUp.items.first?.endsOnLaterDay == false)
    }

    @Test func nextUpFollowsTheEmployeeZoneNotUTCForTheDayBoundary() {
        // 05:30 UTC on 2 Nov is still 23:30 on 1 Nov in Chicago: "today", not "tomorrow".
        let late = Fixture.event("late", "2026-11-02T05:30:00Z", "2026-11-02T06:00:00Z")
        #expect(
            assemble(Fixture.sources(events: [late])).nextUp.items.first?.time
                == .todayAt(ClockTime(hour: 23, minute: 30))
        )
    }

    @Test func anEventInBothObservedWeeksIsListedOnce() {
        let event = Fixture.event("visit", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z")
        var sources = Fixture.sources()
        sources.schedule = [
            Fixture.loaded(CalendarFeed(events: [event])), Fixture.loaded(CalendarFeed(events: [event])),
        ]
        #expect(assemble(sources).nextUp.items.map(\.eventId) == ["visit"])
    }

    @Test func nextUpWaitsForEveryObservedWeekUnlessOneAlreadyHasItems() {
        var sources = Fixture.sources()
        sources.schedule = [Fixture.loaded(CalendarFeed()), Resource(phase: .loading)]
        #expect(!assemble(sources).nextUp.isReady)
        let event = Fixture.event("visit", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z")
        sources.schedule = [Fixture.loaded(CalendarFeed(events: [event])), Resource(phase: .loading)]
        #expect(assemble(sources).nextUp.items.count == 1)
    }

    // MARK: Celebrations

    @Test func aBirthdayAndAnAnniversaryOnTheSameDayBecomeOneCelebration() {
        let milestones = [
            Milestone(kind: .birthday, userId: "u1", displayName: "Jordan Lee", month: 11, day: 1),
            Milestone(
                kind: .workAnniversary,
                userId: "u1",
                displayName: "Jordan Lee",
                month: 11,
                day: 1,
                startYear: 2021
            ),
            Milestone(
                kind: .workAnniversary,
                userId: "u2",
                displayName: "New Hire",
                month: 11,
                day: 1,
                startYear: 2026
            ),
            Milestone(kind: .birthday, userId: "u3", displayName: "Tomorrow", month: 11, day: 2),
        ]
        let celebrations = assemble(Fixture.sources(milestones: milestones)).celebrations
        #expect(
            celebrations == [CelebrationItem(userId: "u1", name: "Jordan Lee", isBirthday: true, anniversaryYears: 5)]
        )
    }

    @Test func milestonesResolveOnTheEmployeesDateAcrossTheFallBackChange() {
        // 04:30 UTC on 1 Nov is 23:30 CDT on 31 Oct: a 31 October birthday is still today.
        let milestones = [Milestone(kind: .birthday, userId: "u1", displayName: "Sam", month: 10, day: 31)]
        let state = assemble(
            Fixture.sources(milestones: milestones),
            Fixture.context(now: Fixture.instant("2026-11-01T04:30:00Z"))
        )
        #expect(state.celebrations.map(\.userId) == ["u1"])
    }

    @Test func aFailedMilestoneLoadIsSurfacedInsteadOfStayingSilent() {
        var sources = Fixture.sources()
        sources.milestones = Resource(phase: .failed(.offline))
        #expect(assemble(sources).celebrationsFailed)
    }
}
