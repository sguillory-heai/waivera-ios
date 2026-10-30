import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ScheduleFeature

/// The Day timeline's rail, today's "Now" line, the period step direction and "Jump to today".
@Suite("Agenda now, rail and period direction")
struct AgendaNowAndRailTests {
    let chicago = Zones.chicago

    private func items(_ feed: CalendarFeed, on date: CalendarDate) -> [AgendaItem] {
        ScheduleAgenda.items(feed: feed, zone: chicago, milestones: .empty, on: date)
    }

    private func marker(_ feed: CalendarFeed, now: String, on date: CalendarDate) -> AgendaNowMarker? {
        let text = ScheduleText(zone: chicago, locale: english)
        return AgendaNowRules.marker(
            items: items(feed, on: date),
            now: instant(now),
            zone: chicago,
            day: date,
            text: text
        )
    }

    // MARK: Rail

    @Test func overnightShiftReadsUntilItsEndOnTheSecondDay() {
        let night = event("night", "2026-10-31T22:00:00-05:00", "2026-11-01T06:00:00-06:00")
        let text = ScheduleText(zone: chicago, locale: english)
        let second = items(CalendarFeed(events: [night]), on: day(2026, 11, 1))
        let first = items(CalendarFeed(events: [night]), on: day(2026, 10, 31))
        #expect(AgendaRowFormatter.rail(second[0], text: text) == AgendaRail(time: "6:00 AM", kicker: "Until"))
        #expect(AgendaRowFormatter.rail(first[0], text: text) == AgendaRail(time: "10:00 PM", kicker: nil))
    }

    @Test func allDayItemsAndCelebrationsReadAllDay() {
        let text = ScheduleText(zone: chicago, locale: english)
        var allDay = CalendarEvent(
            id: "a",
            title: "Offsite",
            start: instant("2026-11-01T05:00:00Z"),
            end: instant("2026-11-02T06:00:00Z")
        )
        allDay.allDay = CalendarEvent.AllDaySpan(start: day(2026, 11, 1), endExclusive: day(2026, 11, 2))
        let rows = items(CalendarFeed(events: [allDay]), on: day(2026, 11, 1))
        #expect(AgendaRowFormatter.rail(rows[0], text: text) == AgendaRail(time: "All day", kicker: nil))
        let celebration = AgendaItem.celebration(
            ScheduleCelebration(userId: "u1", displayName: "Jordan", avatarURL: nil, kind: .birthday, years: nil)
        )
        #expect(AgendaRowFormatter.rail(celebration, text: text).time == "All day")
    }

    @Test func railToneFollowsTheKindAndEndedItemsHaveNone() {
        #expect(AgendaRailTone.of(.event(id: "e"), ended: false) == .teal)
        #expect(AgendaRailTone.of(.timeOff, ended: false) == .violet)
        #expect(AgendaRailTone.of(.holiday, ended: false) == .violet)
        #expect(AgendaRailTone.of(.event(id: "e"), ended: true) == nil)
    }

    @Test func eventRowsNameTheOrganizerAndOnlineMeetings() {
        let meeting = event("m", "2026-10-27T15:00:00Z", "2026-10-27T16:00:00Z") {
            $0.ownerName = "  Alex Rivera "
            $0.isOnline = true
        }
        let silent = event("s", "2026-10-27T17:00:00Z", "2026-10-27T18:00:00Z") { $0.ownerName = " " }
        let text = ScheduleText(zone: chicago, locale: english)
        let rows = items(CalendarFeed(events: [meeting, silent]), on: day(2026, 10, 27))
            .map { AgendaRowFormatter.row($0, day: day(2026, 10, 27), text: text) }
        #expect(rows[0].owner == "Organized by Alex Rivera")
        #expect(rows[0].isOnline)
        #expect(rows[0].accessibilityLabel.contains("Organized by Alex Rivera"))
        #expect(rows[1].owner == nil)
    }

    // MARK: Now

    @Test func nowLineSitsBeforeTheFirstItemStillAheadAndMarksEndedOnes() {
        let night = event("night", "2026-10-26T22:00:00-05:00", "2026-10-27T06:00:00-05:00")
        let visit = event("visit", "2026-10-27T11:00:00-05:00", "2026-10-27T12:00:00-05:00")
        let found = marker(
            CalendarFeed(events: [night, visit]),
            now: "2026-10-27T10:30:00-05:00",
            on: day(2026, 10, 27)
        )
        #expect(found == AgendaNowMarker(time: "10:30 AM", beforeID: "event:visit", endedIDs: ["event:night"]))
    }

    @Test func nowLineGoesLastOnceEverythingEndedAndIsAbsentOnOtherDays() {
        let visit = event("visit", "2026-10-27T08:00:00-05:00", "2026-10-27T09:00:00-05:00")
        let feed = CalendarFeed(events: [visit])
        let late = marker(feed, now: "2026-10-27T20:00:00-05:00", on: day(2026, 10, 27))
        #expect(late?.beforeID == nil)
        #expect(late?.endedIDs == ["event:visit"])
        #expect(marker(feed, now: "2026-10-28T08:30:00-05:00", on: day(2026, 10, 27)) == nil)
    }

    @Test func nowLineNeedsATimedItem() {
        let holiday = Holiday(id: 1, title: "Day off", start: day(2026, 10, 27), end: day(2026, 10, 27))
        #expect(
            marker(CalendarFeed(holidays: [holiday]), now: "2026-10-27T10:00:00-05:00", on: day(2026, 10, 27)) == nil
        )
    }

    /// 1 Nov 2026 repeats 1:00–2:00 in Chicago. An item ending at 1:30 CDT has ended at 1:10 CST
    /// although the wall clock reads earlier; instants decide, and the label names the zone.
    @Test func fallBackRepeatedHourComparesInstantsNotWallTimes() {
        let early = event("early", "2026-11-01T01:00:00-05:00", "2026-11-01T01:30:00-05:00")
        let later = event("later", "2026-11-01T01:20:00-06:00", "2026-11-01T01:50:00-06:00")
        let found = marker(
            CalendarFeed(events: [early, later]),
            now: "2026-11-01T01:10:00-06:00",
            on: day(2026, 11, 1)
        )
        #expect(found?.endedIDs == ["event:early"])
        #expect(found?.beforeID == "event:later")
        #expect(found?.time == "1:10 AM CST")
    }

    // MARK: Period direction and Today

    @Test func periodStepsSayWhichWayTheyWent() {
        let october = PeriodTitle.month(day(2026, 10, 1))
        let november = PeriodTitle.month(day(2026, 11, 1))
        #expect(november.stepDirection(from: october) == 1)
        #expect(october.stepDirection(from: november) == -1)
        #expect(october.stepDirection(from: october) == 0)
        // A view change is a fade, never a slide.
        #expect(PeriodTitle.day(day(2026, 11, 1)).stepDirection(from: october) == 0)
        // A week across two months still steps forward from the week before.
        let lastOctober = PeriodTitle.weekInMonth(start: day(2026, 10, 18), end: day(2026, 10, 24))
        let across = PeriodTitle.weekAcrossMonths(start: day(2026, 10, 25), end: day(2026, 10, 31))
        #expect(across.stepDirection(from: lastOctober) == 1)
    }

    @Test func jumpToTodayShowsOnlyWhenTodayIsOutOfSight() {
        let current = SchedulePreviewStates.schedule(.month)
        #expect(!current.showsJumpToToday)
        var away = current
        away.cells = away.cells.map { cell in
            var copy = cell
            copy.isToday = false
            return copy
        }
        #expect(away.showsJumpToToday)
        var dayView = current
        dayView.view = .day
        #expect(!dayView.showsJumpToToday)
        dayView.selectedDate = dayView.today.adding(days: 1)
        #expect(dayView.showsJumpToToday)
    }

    @Test func largeTextTitlesUseTheShortMonth() {
        let state = SchedulePreviewStates.schedule(.day)
        #expect(state.title == "Sun, November 1")
        #expect(state.shortTitle == "Sun, Nov 1")
        #expect(state.agendaHeadingShort == "Sun, Nov 1")
        #expect(state.agendaHeading == "Sunday, November 1")
    }

    @Test func celebrationCardsCarryTheirEmojiAndKnowTheirOwner() {
        let text = ScheduleText(zone: chicago, locale: english)
        let mine = AgendaItem.celebration(
            ScheduleCelebration(userId: "usr_me", displayName: "Me", avatarURL: nil, kind: .birthday, years: nil)
        )
        let theirs = AgendaItem.celebration(
            ScheduleCelebration(userId: "u2", displayName: "Jo", avatarURL: nil, kind: .anniversary, years: 5)
        )
        let mineRow = AgendaRowFormatter.row(mine, day: day(2026, 11, 1), text: text, myUserId: "usr_me")
        let theirRow = AgendaRowFormatter.row(theirs, day: day(2026, 11, 1), text: text, myUserId: "usr_me")
        #expect(mineRow.isMine)
        #expect(mineRow.emoji == "🎂")
        #expect(!theirRow.isMine)
        #expect(theirRow.emoji == "🎉")
        // Your own card speaks to you by first name; a teammate's names them in full.
        #expect(mineRow.title == "Happy birthday, Me!")
        #expect(mineRow.accessibilityLabel == "Happy birthday, Me!")
        #expect(theirRow.title == "Celebrating Jo's 5-year work anniversary!")
    }

    @Test func yourOwnCelebrationUsesTheFirstWordOfYourNameOrNone() {
        func mine(_ name: String?, _ kind: ScheduleCelebration.Kind, _ years: Int?) -> String {
            CelebrationText.selfSentence(
                ScheduleCelebration(userId: "me", displayName: name, kind: kind, years: years)
            )
        }
        #expect(mine("Alex Rivera", .birthday, nil) == "Happy birthday, Alex!")
        #expect(mine("Alex Rivera", .anniversary, 3) == "Happy 3-year work anniversary, Alex!")
        #expect(mine("Alex Rivera", .both, 3) == "Happy birthday and work anniversary, Alex!")
        #expect(mine(nil, .birthday, nil) == "Happy birthday!")
        #expect(mine("   ", .anniversary, 4) == "Happy 4-year work anniversary!")
        #expect(mine(nil, .both, 2) == "Happy birthday and work anniversary!")
    }
}
