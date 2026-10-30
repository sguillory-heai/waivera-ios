import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraDesign

@testable import ScheduleFeature

enum RGBColorFixture {
    static let purple = RGBColor(hex: 0x7E57C2)
}

@Suite("Milestones and celebrations")
struct MilestoneCalendarTests {
    private func calendar(_ milestones: [Milestone]) -> MilestoneCalendar {
        MilestoneCalendar(MilestoneIndex(milestones))
    }

    @Test func leapDayBirthdayFallsOn28FebruaryInACommonYear() {
        let index = calendar([Milestone(kind: .birthday, userId: "u", displayName: "Lee", month: 2, day: 29)])
        #expect(index.celebrations(on: day(2027, 2, 28)).map(\.userId) == ["u"])
        #expect(index.celebrations(on: day(2027, 3, 1)).isEmpty)
        #expect(index.celebrations(on: day(2028, 2, 28)).isEmpty)
        #expect(index.celebrations(on: day(2028, 2, 29)).map(\.userId) == ["u"])
    }

    @Test func anniversaryInItsStartYearIsNotShown() {
        let index = calendar([
            Milestone(kind: .workAnniversary, userId: "u", displayName: "Sam", month: 11, day: 1, startYear: 2026)
        ])
        #expect(index.celebration(for: "u", on: day(2026, 11, 1)) == nil)
        #expect(index.celebration(for: "u", on: day(2027, 11, 1))?.years == 1)
    }

    @Test func anniversaryWithoutStartYearIsNotShown() {
        let index = calendar([Milestone(kind: .workAnniversary, userId: "u", displayName: "Sam", month: 11, day: 1)])
        #expect(index.celebrations(on: day(2026, 11, 1)).isEmpty)
        #expect(index.count(on: day(2026, 11, 1)) == 0)
    }

    @Test func birthdayAndAnniversaryOnTheSameDayIsAMultipleCelebration() {
        let index = calendar([
            Milestone(kind: .birthday, userId: "u", displayName: "Jordan Lee", month: 11, day: 1),
            Milestone(
                kind: .workAnniversary,
                userId: "u",
                displayName: "Jordan Lee",
                month: 11,
                day: 1,
                startYear: 2021
            ),
        ])
        let celebration = index.celebration(for: "u", on: day(2026, 11, 1))
        #expect(celebration?.kind == .both)
        #expect(celebration?.years == 5)
        guard let celebration else { return }
        let text = CelebrationText(celebration)
        #expect(text.compact == "Birthday + 5-yr anniversary")
        #expect(text.full == "It's Jordan Lee's birthday and 5-year work anniversary!")
        #expect(text.accessible == "Jordan Lee is celebrating a birthday and 5-year work anniversary today.")
        #expect(MilestoneBadge(celebration: celebration, avatarSize: 40).glyph == .party)
    }

    @Test func singleCelebrationsKeepTheirType() {
        let birthday = ScheduleCelebration(userId: "a", displayName: nil, kind: .birthday, years: nil)
        let anniversary = ScheduleCelebration(userId: "b", displayName: "Sam Ortiz", kind: .anniversary, years: 5)
        #expect(CelebrationText(birthday).full == "It's This employee's birthday today!")
        #expect(CelebrationText(birthday).compact == "Birthday today")
        #expect(CelebrationText(anniversary).compact == "5-year anniversary")
        #expect(CelebrationText(anniversary).full == "Celebrating Sam Ortiz's 5-year work anniversary!")
        #expect(CelebrationText(anniversary).accessible == "Sam Ortiz is celebrating a 5-year work anniversary today.")
        #expect(CelebrationText.kindLabel(anniversary) == "5-year work anniversary")
    }

    @Test func anniversaryYearsShowInTheBadgeOnlyAt40PointsOrMore() {
        let anniversary = ScheduleCelebration(userId: "b", displayName: "Sam", kind: .anniversary, years: 5)
        #expect(MilestoneBadge(celebration: anniversary, avatarSize: 40).years == 5)
        #expect(MilestoneBadge(celebration: anniversary, avatarSize: 32).years == nil)
        #expect(MilestoneBadge(celebration: anniversary, avatarSize: 32).glyph == .award)
        #expect(MilestoneBadge.size(forAvatar: 32) == 17)
        #expect(MilestoneBadge.size(forAvatar: 76) == 33)
    }

    @Test func monthGridLookupDoesNotScanEveryMilestonePerCell() {
        // 400 employees spread over the year: each cell evaluates only that day's people.
        let milestones = (0..<400).map { index in
            Milestone(
                kind: .birthday,
                userId: "u\(index)",
                displayName: "P\(index)",
                month: index % 12 + 1,
                day: index % 28 + 1
            )
        }
        let index = calendar(milestones)
        for cell in SchedulePeriods.cells(.month, containing: day(2026, 10, 1)) {
            let expected = milestones.filter { $0.month == cell.month && $0.day == cell.day }.count
            #expect(index.candidates(on: cell).count == expected)
            #expect(index.count(on: cell) == expected)
        }
    }

    @Test func milestoneOnTheFallBackDateMatchesTheEmployeesLocalDate() {
        // 23:30 CST on 1 Nov 2026 is already 2 Nov in UTC; the birthday follows Chicago.
        let now = instant("2026-11-02T05:30:00Z")
        let index = calendar([Milestone(kind: .birthday, userId: "u", displayName: "Lee", month: 11, day: 1)])
        #expect(index.count(on: CalendarDate(now, in: Zones.chicago)) == 1)
        #expect(index.count(on: CalendarDate(now, in: Zones.utc)) == 0)
    }
}

@Suite("Schedule text")
struct ScheduleTextTests {
    @Test func weekdayHeadersStartOnSunday() {
        let text = ScheduleText(zone: Zones.chicago, locale: english)
        #expect(text.weekdayHeaders == ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"])
        #expect(text.weekdayHeadersNarrow == ["S", "M", "T", "W", "T", "F", "S"])
    }

    @Test func theWeekStripHasAOneLetterWeekdayForTheLargestText() {
        let text = ScheduleText(zone: Zones.chicago, locale: english)
        #expect(text.weekdayShort(day(2026, 11, 2)) == "Mon")
        #expect(text.weekdayNarrow(day(2026, 11, 2)) == "M")
        let state = SchedulePreviewStates.schedule(.week)
        #expect(state.cells.allSatisfy { $0.weekdayNarrow.count == 1 })
        #expect(state.weekdayHeadersNarrow.count == 7)
    }

    @Test func clocksAreTwelveHourInTheScheduleZone() {
        let chicago = ScheduleText(zone: Zones.chicago, locale: english)
        let tokyo = ScheduleText(zone: Zones.tokyo, locale: english)
        let start = instant("2026-10-27T20:00:00Z")
        #expect(chicago.clock(start) == "3:00 PM")
        #expect(tokyo.clock(start) == "5:00 AM")
        #expect(chicago.dateTime(start, currentYear: 2026) == "Tue, Oct 27, 3:00 PM")
        #expect(chicago.dateTime(start, currentYear: 2025) == "Tue, Oct 27, 2026, 3:00 PM")
    }

    @Test func literalDatesNeverShiftAcrossZones() {
        for zone in [Zones.chicago, Zones.tokyo, Zones.sydney, Zones.utc] {
            let text = ScheduleText(zone: zone, locale: english)
            #expect(text.fullDay(day(2026, 11, 1)) == "Sunday, November 1")
            #expect(text.fullDay(day(2026, 3, 8)) == "Sunday, March 8")
            #expect(text.dayNumber(day(2026, 4, 5)) == "5")
        }
    }

    @Test func timeOffPartsMatchTheSpecSubtitle() {
        #expect(ScheduleCopy.sentenceCase("APPROVED") == "Approved")
        #expect(ScheduleCopy.sentenceCase("CANCELLATION_PENDING") == "Cancellation pending")
        #expect(ScheduleCopy.sentenceCase(" ") == nil)
        #expect(ScheduleCopy.requestTypeLabel("HALF_DAY_AM") == "half day am")
        #expect(ScheduleCopy.requestTypeLabel(nil) == "full day")
    }

    @Test func ownerColourParsesServerHexAndRejectsAnythingElse() {
        #expect(ScheduleCopy.ownerColor("#7E57C2") == RGBColorFixture.purple)
        #expect(ScheduleCopy.ownerColor("7e57c2") == RGBColorFixture.purple)
        #expect(ScheduleCopy.ownerColor("#807E57C2") == RGBColor(hex: 0x7E57C2, alpha: Double(0x80) / 255))
        for bad in [nil, "", "purple", "#12345", "#GGGGGG", "rgb(1,2,3)"] as [String?] {
            #expect(ScheduleCopy.ownerColor(bad) == nil)
        }
    }

    @Test func gridCellLabelsSayWhatTheDotsShow() {
        let text = ScheduleText(zone: Zones.chicago, locale: english)
        let label = ScheduleStateBuilder.cellLabel(
            day(2026, 11, 1),
            today: day(2026, 11, 1),
            inPeriod: false,
            marker: DayMarker(events: 2, celebrations: 1),
            text: text
        )
        #expect(label == "Sunday, November 1, today, 2 events, 1 celebration, outside this month")
    }
}
