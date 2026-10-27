import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ScheduleFeature

@Suite("Schedule periods")
struct SchedulePeriodsTests {
    @Test func monthViewInOctober2026Has42CellsFromTheSundayOnOrBefore1October() {
        let cells = SchedulePeriods.cells(.month, containing: day(2026, 10, 27))
        #expect(cells.count == 42)
        #expect(cells.first == day(2026, 9, 27))
        #expect(cells.last == day(2026, 11, 7))
        #expect(cells.enumerated().allSatisfy { index, date in (date.weekday == 1) == index.isMultiple(of: 7) })
    }

    @Test func monthViewFetchesTheWholeRenderedGridNotJustTheMonth() {
        let interval = SchedulePeriods.fetchInterval(.month, containing: day(2026, 10, 15), in: Zones.chicago)
        #expect(interval.start == instant("2026-09-27T00:00:00-05:00"))
        #expect(interval.end == instant("2026-11-08T00:00:00-06:00"))
    }

    @Test func steppingMonthFrom31JanuaryLandsOn28FebruaryThen28March() {
        let february = SchedulePeriods.step(.month, from: day(2026, 1, 31), by: 1)
        let march = SchedulePeriods.step(.month, from: february, by: 1)
        #expect(february == day(2026, 2, 28))
        #expect(march == day(2026, 3, 28))
        #expect(SchedulePeriods.step(.month, from: day(2026, 1, 15), by: -1) == day(2025, 12, 15))
    }

    @Test func weekStepAdvancesTheRangeByExactlySevenDays() {
        let start = day(2026, 10, 27)
        let next = SchedulePeriods.step(.week, from: start, by: 1)
        #expect(next == day(2026, 11, 3))
        let first = SchedulePeriods.fetchInterval(.week, containing: start, in: Zones.chicago)
        let second = SchedulePeriods.fetchInterval(.week, containing: next, in: Zones.chicago)
        #expect(first.end == second.start)
        #expect(CalendarDate(second.start, in: Zones.chicago) == day(2026, 11, 1))
        #expect(CalendarDate(second.end, in: Zones.chicago) == day(2026, 11, 8))
    }

    @Test func dayStepMovesOneDayAndDayViewHasNoGrid() {
        #expect(SchedulePeriods.step(.day, from: day(2026, 10, 31), by: 1) == day(2026, 11, 1))
        #expect(SchedulePeriods.cells(.day, containing: day(2026, 10, 31)).isEmpty)
        #expect(SchedulePeriods.cells(.week, containing: day(2026, 10, 31)).count == 7)
    }

    @Test func periodTitlesFollowTheSpecShapes() {
        let text = ScheduleText(zone: Zones.chicago, locale: english)
        #expect(text.title(SchedulePeriods.title(.month, for: day(2026, 10, 27))) == "October 2026")
        #expect(text.title(SchedulePeriods.title(.day, for: day(2026, 10, 27))) == "Tue, October 27")
        #expect(text.title(SchedulePeriods.title(.week, for: day(2026, 10, 27))) == "October 25–31, 2026")
        #expect(text.title(SchedulePeriods.title(.week, for: day(2026, 12, 1))) == "November 29 – December 5")
    }

    @Test func monthGridContainingChicagoFallBackIsOneHourLongerThan42Days() {
        let interval = SchedulePeriods.fetchInterval(.month, containing: day(2026, 11, 1), in: Zones.chicago)
        #expect(interval.duration == 42 * 86_400 + 3_600)
    }

    @Test func weekContainingChicagoSpringForwardIsOneHourShort() {
        let interval = SchedulePeriods.fetchInterval(.week, containing: day(2026, 3, 10), in: Zones.chicago)
        #expect(interval.duration == 7 * 86_400 - 3_600)
        #expect(interval.start == instant("2026-03-08T06:00:00Z"))
    }

    @Test func southernHemisphereGridsShiftTheOtherWay() {
        // Sydney springs forward on 4 Oct 2026 and falls back on 5 Apr 2026.
        let spring = SchedulePeriods.fetchInterval(.week, containing: day(2026, 10, 6), in: Zones.sydney)
        #expect(spring.duration == 7 * 86_400 - 3_600)
        let autumn = SchedulePeriods.fetchInterval(.week, containing: day(2026, 4, 7), in: Zones.sydney)
        #expect(autumn.duration == 7 * 86_400 + 3_600)
        #expect(autumn.start == instant("2026-04-04T13:00:00Z"))
    }

    @Test func spillDaysAreOutsideThePeriodOnlyInMonthView() {
        #expect(!SchedulePeriods.isInPeriod(day(2026, 9, 27), view: .month, anchor: day(2026, 10, 1)))
        #expect(SchedulePeriods.isInPeriod(day(2026, 10, 31), view: .month, anchor: day(2026, 10, 1)))
        #expect(SchedulePeriods.isInPeriod(day(2026, 11, 1), view: .week, anchor: day(2026, 10, 31)))
    }
}

@Suite("Schedule zone")
struct ScheduleZoneTests {
    @Test func savedNamedZoneIsUsed() {
        let zone = ScheduleZone.resolve(savedIdentifier: "Australia/Sydney")
        #expect(zone.identifier == "Australia/Sydney")
        #expect(!zone.isFallback)
    }

    @Test func missingInvalidOrFixedOffsetZonesFallBackToChicagoNeverTheDevice() {
        for raw in [nil, "", "  ", "Mars/Olympus", "GMT-6", "CST"] as [String?] {
            let zone = ScheduleZone.resolve(savedIdentifier: raw)
            #expect(zone.identifier == "America/Chicago", "\(raw ?? "nil")")
            #expect(zone.isFallback)
        }
    }

    @Test func zoneNoticeShowsWhenTheSavedZoneDiffersFromTheDevice() {
        let chicago = ScheduleZone.resolve(savedIdentifier: "America/Chicago")
        #expect(ZoneNotice.make(zone: chicago, deviceZone: Zones.tokyo) != nil)
        #expect(ZoneNotice.make(zone: chicago, deviceZone: Zones.chicago) == nil)
    }

    @Test func zoneNoticeSaysWhenTheFallbackZoneIsInEffect() {
        let fallback = ScheduleZone.resolve(savedIdentifier: nil)
        #expect(ZoneNotice.make(zone: fallback, deviceZone: Zones.chicago) != nil)
        let text = ScheduleText(zone: fallback.timeZone, locale: english)
        let notice = ScheduleStateBuilder.zoneNotice(zone: fallback, deviceZone: Zones.chicago, text: text)
        #expect(notice?.hasPrefix("Your profile has no time zone") == true)
    }
}
