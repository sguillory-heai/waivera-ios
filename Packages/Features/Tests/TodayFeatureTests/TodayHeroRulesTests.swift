import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import TodayFeature

/// The hero's rules: the greeting in the saved zone, the handled tally behind the count-only
/// ring, the subline by kind, the stat tiles and the "Your day" track, across a DST change.
struct TodayHeroRulesTests {
    private func assemble(_ sources: TodaySources, _ context: TodayContext = Fixture.context()) -> TodayState {
        TodayAssembler.assemble(sources, context: context)
    }

    // MARK: Greeting

    @Test func theGreetingFollowsTheSavedZoneNotTheDevice() {
        #expect(GreetingRules.dayPart(Fixture.now, zone: Fixture.chicago) == .morning)
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .current
        #expect(GreetingRules.dayPart(Fixture.now, zone: tokyo) == .evening, "01:30 in Tokyo is still the night")
    }

    @Test func theGreetingCrossesFiveAMOnTheClockAfterTheFallBackChange() {
        // 10:30Z on 1 November 2026 is 4:30 CST, after clocks went back; a fixed CDT offset would say 5:30.
        #expect(GreetingRules.dayPart(Fixture.instant("2026-11-01T10:30:00Z"), zone: Fixture.chicago) == .evening)
        #expect(GreetingRules.dayPart(Fixture.instant("2026-11-01T11:00:00Z"), zone: Fixture.chicago) == .morning)
        #expect(GreetingRules.dayPart(Fixture.instant("2026-11-01T18:00:00Z"), zone: Fixture.chicago) == .afternoon)
        #expect(GreetingRules.dayPart(Fixture.instant("2026-11-01T23:00:00Z"), zone: Fixture.chicago) == .evening)
    }

    @Test func theGreetingNamesTheFirstNameElseTheFirstWordOfTheDisplayNameNeverTheEmail() {
        #expect(GreetingRules.firstName(" Alex ", displayName: "Alexander Rivera") == "Alex")
        #expect(GreetingRules.firstName(nil, displayName: "Priya  Raman") == "Priya")
        #expect(GreetingRules.firstName("  ", displayName: nil) == nil)
        #expect(TodayStrings.greeting(Greeting(part: .morning, firstName: "Alex")) == "Good morning, Alex")
        #expect(TodayStrings.greeting(Greeting(part: .evening, firstName: nil)) == "Good evening")
    }

    // MARK: Handled tally

    private func observation(_ open: Set<String>, undoable: Set<String> = [], day: CalendarDate = Fixture.today)
        -> HandledObservation
    {
        HandledObservation(userId: Fixture.viewerId, day: day, open: open, undoable: undoable)
    }

    @Test func theFirstLookStartsFromZeroAndEachItemThatLeavesCountsOnce() {
        let first = HandledToday.advance(nil, observation(["dm-1", "dm-2", "ticket-3"]))
        #expect(first.handled == 0)
        #expect(first.total == 3)
        let second = HandledToday.advance(first, observation(["dm-2"]))
        #expect(second.handled == 2)
        #expect(HandledToday.advance(second, observation(["dm-2"])) == second, "the same look counts nothing twice")
    }

    @Test func anUndoneInvitationAnswerTakesItsCountBackButANewMessageIsJustOpenAgain() {
        let start = HandledToday.advance(nil, observation(["invite-a", "dm-1"], undoable: ["invite-a"]))
        let answered = HandledToday.advance(start, observation([]))
        #expect(answered.handled == 2)
        let undone = HandledToday.advance(answered, observation(["invite-a", "dm-1"], undoable: ["invite-a"]))
        #expect(undone.handled == 1, "the invitation came back; the chat has a new message and stays handled")
        #expect(undone.open == ["invite-a", "dm-1"])
    }

    @Test func aNewDayInTheSavedZoneOrAnotherPersonStartsAgain() {
        let yesterday = HandledToday.advance(nil, observation(["dm-1"], day: Fixture.today.adding(days: -1)))
        let handled = HandledToday.advance(yesterday, observation([], day: Fixture.today.adding(days: -1)))
        #expect(handled.handled == 1)
        #expect(HandledToday.advance(handled, observation(["dm-2"])).handled == 0)
        let other = HandledObservation(userId: "usr_other", day: Fixture.today.adding(days: -1), open: [])
        #expect(HandledToday.advance(handled, other).handled == 0)
    }

    @Test func theTallyIsOnlyFedWhenEverySourceBehindNeedsYouHasLoaded() {
        var sources = Fixture.sources(conversations: [Fixture.direct(7)])
        let context = Fixture.context(userId: Fixture.viewerId)
        #expect(assemble(sources, context).handledObservation?.open == ["dm-7"])
        sources.activity = Resource()
        let partial = assemble(sources, context)
        #expect(partial.handledObservation == nil, "a missing feed never reads as its mentions handled")
        #expect(partial.progress == TodayProgress(handled: 0, open: 1))
        #expect(assemble(Fixture.sources(conversations: [Fixture.direct(7)])).handledObservation == nil, "no user")
    }

    @Test func theRingCountsWhatLeftSinceTheSavedTallyAndKeepsItWhileASourceReloads() {
        let saved = HandledToday.advance(nil, observation(["dm-7", "dm-8", "invite-x"]))
        let context = Fixture.context(userId: Fixture.viewerId, handled: saved)
        let state = assemble(Fixture.sources(conversations: [Fixture.direct(7)]), context)
        #expect(state.progress == TodayProgress(handled: 2, open: 1))
        var reloading = Fixture.sources(conversations: [Fixture.direct(7)])
        reloading.activity = Resource()
        #expect(
            assemble(reloading, context).progress == TodayProgress(handled: 0, open: 1),
            "without a full look the ring keeps the saved count"
        )
    }

    @Test func allCaughtUpNeedsNothingOpenAndNothingUnread() {
        let state = assemble(Fixture.sources(), Fixture.context(userId: Fixture.viewerId))
        #expect(state.isAllCaughtUp)
        #expect(state.progress == TodayProgress(handled: 0, open: 0))
    }

    // MARK: Subline and kinds

    @Test func theSublineListsKindsInOrderWithNoBreakSpacesAndDropsEmptyKinds() {
        let line = TodayStrings.subline([.ticket: 1, .message: 2, .notSent: 1, .invitation: 0])
        #expect(line == "1\u{00A0}not\u{00A0}sent\u{00A0}· 2\u{00A0}messages\u{00A0}· 1\u{00A0}ticket")
        #expect(TodayStrings.subline([:]) == nil)
        #expect(TodayStrings.subline([.mention: 0]) == nil)
    }

    @Test func aFailedSendLeadsNeedsYouAndCountsAsNotSent() {
        var sources = Fixture.sources(conversations: [Fixture.direct(7, unread: 2), Fixture.direct(8, unread: 0)])
        sources.failedSends = [8]
        let section = assemble(sources).needsYou
        #expect(section.items.map(\.id) == ["not-sent-8", "dm-7"])
        #expect(section.kinds == [.notSent: 1, .message: 1])
        #expect(TodayStrings.needsYouHeadline(open: 2) == "2 things need you")
        #expect(TodayStrings.needsYouHeadline(open: 1) == "1 thing needs you")
        #expect(TodayStrings.needsYouHeadline(open: 0) == "Nothing needs you right now")
    }

    @Test func theRewardLineNamesTheCountAndTheFirstName() {
        #expect(TodayStrings.caughtUp(handled: 9, firstName: "Alex") == "All 9 handled today. Nice work, Alex.")
        #expect(TodayStrings.caughtUp(handled: 1, firstName: nil) == "1 handled today. Nice work.")
        #expect(
            TodayStrings.caughtUp(handled: 0, firstName: "Alex") == "Enjoy the calm. Anything new will show up here."
        )
        #expect(TodayStrings.ring(TodayProgress(handled: 5, open: 4)) == "5 of 9 handled today")
    }

    @Test func aMentionSplitsIntoWhoAndAQuote() {
        let quoted = QuotedSummary.of("Priya Raman mentioned you: \"the Hughes visit moved to 10\"")
        #expect(quoted == QuotedSummary(lead: "Priya Raman mentioned you", quote: "the Hughes visit moved to 10"))
        #expect(
            QuotedSummary.of("You were added to #care-team")
                == QuotedSummary(lead: nil, quote: "You were added to #care-team")
        )
        #expect(QuotedSummary.of(": \"only a quote\"").lead == nil)
        #expect(TodayStrings.mentionHeadline(lead: nil, actor: "Sam") == "Sam mentioned you")
        #expect(TodayStrings.nonBreakingHyphens("WAIV-2527") == "WAIV\u{2011}2527")
    }

    // MARK: Up next

    @Test func theFeaturedItemIsTheFirstTimedOneAndTheRestFollow() {
        let state = assemble(
            Fixture.sources(events: [
                Fixture.allDay("dst", from: Fixture.today, until: Fixture.today.adding(days: 1)),
                Fixture.event("visit", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z"),
                Fixture.event("tomorrow", "2026-11-02T15:00:00Z", "2026-11-02T16:00:00Z"),
            ])
        )
        #expect(state.nextUp.featured?.eventId == "visit")
        #expect(state.nextUp.others.map(\.eventId) == ["dst", "tomorrow"])
        #expect(state.nextUp.items.map(\.startsToday) == [true, true, false])
    }

    // MARK: Stats

    @Test func statsCountAttendedEventsInTheSavedWeekAndChatsWithUnread() {
        var archived = Fixture.direct(9, unread: 2)
        archived.isArchived = true
        let state = assemble(
            Fixture.sources(
                conversations: [Fixture.direct(7, unread: 2), Fixture.direct(8, unread: 0), archived, Fixture.bot(14)],
                events: [
                    Fixture.event("today", "2026-11-01T17:00:00Z", "2026-11-01T18:00:00Z"),
                    Fixture.event("pending", "2026-11-01T19:00:00Z", "2026-11-01T20:00:00Z", response: .pending),
                    Fixture.event("declined", "2026-11-01T19:00:00Z", "2026-11-01T20:00:00Z", response: .declined),
                    Fixture.event("tuesday", "2026-11-03T15:00:00Z", "2026-11-03T16:00:00Z"),
                    // 23:30 CST on Saturday 7 November is 05:30Z on the 8th: still this week where she works.
                    Fixture.event("saturday", "2026-11-08T05:30:00Z", "2026-11-08T05:45:00Z"),
                    Fixture.event("next-week", "2026-11-09T15:00:00Z", "2026-11-09T16:00:00Z"),
                ]
            )
        )
        #expect(state.stats == TodayStats(eventsToday: 1, unreadChats: 2, eventsThisWeek: 3))
    }

    @Test func statsShowADashUntilTheirSourceLoads() {
        var sources = Fixture.sources()
        sources.schedule = [Resource(), Resource()]
        sources.conversations = Resource()
        #expect(assemble(sources).stats == TodayStats())
        let tile = TodayStrings.stat(nil, label: "today.stat.eventsToday")
        #expect(tile.value == "–")
        #expect(tile.spoken == "events today, still loading")
        #expect(TodayStrings.stat(1, label: "today.stat.unreadChats").spoken == "1 unread chat")
        #expect(TodayStrings.handledStat(TodayProgress(handled: 5, open: 0)).value == "5/5")
    }

    // MARK: Your day

    @Test func theTrackRunsEightToSixAndPlacesEventsAndNowInTheSavedZone() throws {
        let state = assemble(
            Fixture.sources(events: [
                Fixture.event("visit", "2026-11-01T15:00:00Z", "2026-11-01T16:00:00Z"),
                Fixture.event("call", "2026-11-01T15:30:00Z", "2026-11-01T16:30:00Z"),
                Fixture.allDay("dst", from: Fixture.today, until: Fixture.today.adding(days: 1)),
                Fixture.event("pending", "2026-11-01T20:00:00Z", "2026-11-01T21:00:00Z", response: .pending),
            ])
        )
        let day = try #require(state.day)
        #expect(day.windowStart == ClockTime(hour: 8, minute: 0))
        #expect(day.windowEnd == ClockTime(hour: 18, minute: 0))
        #expect(day.eventCount == 2, "all-day and unanswered items stay off the track")
        #expect(day.blocks.map(\.eventId) == ["visit", "call"])
        #expect(abs(day.blocks[0].start - 0.1) < 0.0001)
        #expect(abs(day.blocks[0].end - 0.2) < 0.0001)
        #expect(day.blocks.map(\.tone) == [0, 1])
        #expect(abs((day.now ?? -1) - 0.25) < 0.0001)
        #expect(day.ticks.count == 9)
        #expect(day.labels.map(\.time.hour) == [8, 10, 12, 14, 16, 18])
        #expect(day.scheduled == 90 * 60, "the overlapping half hour counts once")
        #expect(TodayStrings.daySummary(day) == "2 events · 1 hr 30 min scheduled")
    }

    @Test func onTheFallBackDayTheTrackMeasuresTheRealTwentyFiveHourDay() throws {
        // 05:30Z is 00:30 CDT; 09:00Z is 03:00 CST, after the repeated hour. The window runs from
        // local midnight to 6 PM: 19 real hours, not 18.
        let state = assemble(
            Fixture.sources(events: [Fixture.event("night", "2026-11-01T05:30:00Z", "2026-11-01T09:00:00Z")])
        )
        let day = try #require(state.day)
        #expect(day.windowStart == ClockTime(hour: 0, minute: 0))
        #expect(abs(day.blocks[0].start - 0.5 / 19) < 0.0001)
        #expect(abs(day.blocks[0].end - 4.0 / 19) < 0.0001)
        #expect(day.ticks.count == 17)
        #expect(day.ticks.contains { abs($0 - 4.0 / 19) < 0.0001 }, "3 AM sits where its instant falls")
        #expect(day.scheduled == 3.5 * 3_600)
    }

    @Test func anOpenDayHasNoEventsAndNoTrackUntilTheScheduleLoads() throws {
        let open = try #require(assemble(Fixture.sources()).day)
        #expect(open.eventCount == 0)
        #expect(TodayStrings.daySummary(open) == "Your day is wide open.")
        var loading = Fixture.sources()
        loading.schedule = [Resource(), Resource()]
        #expect(assemble(loading).day == nil)
    }

    @Test func hourLabelsThatWouldCollideAreDroppedNeverOverlapped() {
        let xs = AxisLabelPlacement.place(centers: [0, 0.5, 1], widths: [30, 30, 30], total: 100, gap: 8)
        #expect(xs == [0, nil, 70])
        #expect(
            AxisLabelPlacement.place(centers: [0, 0.5, 1], widths: [20, 20, 20], total: 200, gap: 8) == [0, 90, 180]
        )
    }
}
