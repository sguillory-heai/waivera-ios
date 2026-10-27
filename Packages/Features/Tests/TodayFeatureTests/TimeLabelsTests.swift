import Foundation
import Testing
import WaiveraAPI

@testable import TodayFeature

/// Relative and clock labels in the employee's saved zone, including both DST changes.
struct TimeLabelsTests {
    private let zone = Fixture.chicago
    private let now = Fixture.now  // 10:30 CST on 1 Nov 2026, the day DST ends

    private func instant(_ raw: String) -> Date { Fixture.instant(raw) }

    @Test func startsWithinTheHourReadsInMinutesRoundedUp() {
        #expect(TimeLabels.upcoming(start: now + 25 * 60, end: nil, now: now, zone: zone) == .inMinutes(25))
        #expect(TimeLabels.upcoming(start: now + 30, end: nil, now: now, zone: zone) == .inMinutes(1))
        #expect(TimeLabels.upcoming(start: now + 58 * 60 + 1, end: nil, now: now, zone: zone) == .inMinutes(59))
    }

    @Test func startsWithinSixHoursReadsInHoursAndMinutes() {
        #expect(TimeLabels.upcoming(start: now + 3_600, end: nil, now: now, zone: zone) == .inHours(1, minutes: 0))
        #expect(TimeLabels.upcoming(start: now + 359 * 60, end: nil, now: now, zone: zone) == .inHours(5, minutes: 59))
    }

    @Test func laterTodayTomorrowAndOtherDaysUseTheClockInTheSavedZone() {
        // 19:00 CST on 1 Nov is already 2 Nov in UTC.
        #expect(
            TimeLabels.upcoming(start: instant("2026-11-02T01:00:00Z"), end: nil, now: now, zone: zone)
                == .todayAt(ClockTime(hour: 19, minute: 0))
        )
        #expect(
            TimeLabels.upcoming(start: instant("2026-11-02T15:00:00Z"), end: nil, now: now, zone: zone)
                == .tomorrowAt(ClockTime(hour: 9, minute: 0))
        )
        #expect(
            TimeLabels.upcoming(start: instant("2026-11-04T15:00:00Z"), end: nil, now: now, zone: zone)
                == .onDayAt(Fixture.date(2026, 11, 4), ClockTime(hour: 9, minute: 0))
        )
    }

    @Test func anItemInProgressReadsNowUntilItsLocalEnd() {
        let label = TimeLabels.upcoming(start: now - 600, end: instant("2026-11-01T18:00:00Z"), now: now, zone: zone)
        #expect(label == .now(until: ClockTime(hour: 12, minute: 0)))
        #expect(TimeLabels.upcoming(start: now, end: nil, now: now, zone: zone) == .now(until: nil))
    }

    @Test func fallBackCountsNinetyRealMinutesAcrossTheRepeatedHour() {
        // 01:30 CDT (first pass) to 02:00 CST: the wall clock moves 30 minutes, real time 90.
        let label = TimeLabels.upcoming(
            start: instant("2026-11-01T08:00:00Z"),
            end: nil,
            now: instant("2026-11-01T06:30:00Z"),
            zone: zone
        )
        #expect(label == .inHours(1, minutes: 30))
    }

    @Test func springForwardCountsOneRealHourAcrossTheSkippedHour() {
        // 01:30 CST to 03:30 CDT on 8 March 2026: the wall clock moves two hours, real time one.
        let before = instant("2026-03-08T07:30:00Z")
        #expect(
            TimeLabels.upcoming(start: instant("2026-03-08T08:30:00Z"), end: nil, now: before, zone: zone)
                == .inHours(1, minutes: 0)
        )
        // 20:00 CDT on 8 March, after the change.
        #expect(
            TimeLabels.upcoming(start: instant("2026-03-09T01:00:00Z"), end: nil, now: before, zone: zone)
                == .todayAt(ClockTime(hour: 20, minute: 0))
        )
    }

    @Test func theDeviceZoneNeverChangesTheLabels() {
        // Every rule takes the saved zone explicitly; a far-away zone gives the same answers.
        let tokyo = TimeZone(identifier: "Asia/Tokyo") ?? .current
        let evening = instant("2026-11-02T01:00:00Z")
        #expect(
            TimeLabels.upcoming(start: evening, end: nil, now: now, zone: zone)
                == .todayAt(ClockTime(hour: 19, minute: 0))
        )
        #expect(
            TimeLabels.upcoming(start: evening, end: nil, now: now, zone: tokyo)
                != .todayAt(ClockTime(hour: 19, minute: 0))
        )
        #expect(
            TimeLabels.past(instant("2026-11-01T05:30:00Z"), now: now, zone: zone)
                == .todayAt(ClockTime(hour: 0, minute: 30))
        )
    }

    @Test func allDayItemsReadTodayTomorrowOrTheirDate() {
        let today = Fixture.today
        #expect(TimeLabels.allDay(start: today, endExclusive: today.adding(days: 1), today: today) == .allDayToday)
        #expect(
            TimeLabels.allDay(start: today.adding(days: -2), endExclusive: today.adding(days: 1), today: today)
                == .allDayToday
        )
        #expect(TimeLabels.allDay(start: today.adding(days: 1), endExclusive: nil, today: today) == .allDayTomorrow)
        #expect(
            TimeLabels.allDay(start: today.adding(days: 3), endExclusive: nil, today: today)
                == .allDayOn(today.adding(days: 3))
        )
    }

    @Test func pastLabelsFollowTheChatListRules() {
        #expect(TimeLabels.past(now - 59, now: now, zone: zone) == .justNow)
        #expect(TimeLabels.past(now + 30, now: now, zone: zone) == .justNow)
        #expect(TimeLabels.past(now - (5 * 60 + 20), now: now, zone: zone) == .minutesAgo(5))
        #expect(
            TimeLabels.past(instant("2026-11-01T14:00:00Z"), now: now, zone: zone)
                == .todayAt(ClockTime(hour: 8, minute: 0))
        )
        #expect(TimeLabels.past(instant("2026-10-31T20:00:00Z"), now: now, zone: zone) == .yesterday)
        #expect(
            TimeLabels.past(instant("2026-10-20T13:02:44Z"), now: now, zone: zone)
                == .onDate(Fixture.date(2026, 10, 20))
        )
    }

    @Test func pastLabelsPlaceTheRepeatedFallBackHourOnTheRightDay() {
        // 00:30 CDT on 1 Nov is today; 23:30 CDT on 31 Oct is yesterday, both within 25 hours.
        #expect(
            TimeLabels.past(instant("2026-11-01T05:30:00Z"), now: now, zone: zone)
                == .todayAt(ClockTime(hour: 0, minute: 30))
        )
        #expect(TimeLabels.past(instant("2026-11-01T04:30:00Z"), now: now, zone: zone) == .yesterday)
    }
}
