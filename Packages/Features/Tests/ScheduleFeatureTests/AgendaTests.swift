import Foundation
import Testing
import WaiveraAPI
import WaiveraData

@testable import ScheduleFeature

@Suite("Agenda and markers")
struct AgendaTests {
    let chicago = Zones.chicago

    private func eventIds(_ items: [AgendaItem]) -> [String] {
        items.compactMap { item in
            if case .event(let event, _) = item { return event.id }
            return nil
        }
    }

    private func rows(_ feed: CalendarFeed, on date: CalendarDate, zone: TimeZone = Zones.chicago) -> [AgendaRow] {
        let text = ScheduleText(zone: zone, locale: english)
        return ScheduleAgenda.items(feed: feed, zone: zone, milestones: .empty, on: date)
            .map { AgendaRowFormatter.row($0, day: date, text: text) }
    }

    @Test func agendaOrderIsMilestoneHolidayTimeOffThenEventsByStartInstant() {
        var timeOff = CalendarTimeOff(
            id: 1,
            start: instant("2026-10-27T05:00:00Z"),
            end: instant("2026-10-28T05:00:00Z"),
            leaveType: "Paid time off"
        )
        timeOff.status = "APPROVED"
        // Mixed representations: string order would put the offset one first.
        let late = event("late", "2026-10-27T19:30:00Z", "2026-10-27T20:00:00Z")
        let early = event("early", "2026-10-27T10:00:00-05:00", "2026-10-27T11:00:00-05:00")
        let feed = CalendarFeed(
            events: [late, early],
            timeOff: [timeOff],
            holidays: [Holiday(id: 3, title: "Founders day", start: day(2026, 10, 27), end: day(2026, 10, 27))]
        )
        let milestones = MilestoneCalendar(
            MilestoneIndex([Milestone(kind: .birthday, userId: "u1", displayName: "Jordan Lee", month: 10, day: 27)])
        )
        let items = ScheduleAgenda.items(feed: feed, zone: chicago, milestones: milestones, on: day(2026, 10, 27))
        #expect(items.map(\.id) == ["celebration:u1", "holiday:3", "timeoff:1", "event:early", "event:late"])
    }

    @Test func eventFrom23To01AppearsOnBothDays() {
        let overnight = event("night", "2026-10-27T23:00:00-05:00", "2026-10-28T01:00:00-05:00")
        let feed = CalendarFeed(events: [overnight])
        let first = rows(feed, on: day(2026, 10, 27))
        let second = rows(feed, on: day(2026, 10, 28))
        #expect(first.map(\.id) == ["event:night"])
        #expect(second.map(\.id) == ["event:night"])
        #expect(first.first?.subtitle == "11:00 PM – Wed 1:00 AM")
        #expect(second.first?.subtitle == "Tue 11:00 PM – 1:00 AM")
    }

    @Test func dayDotsTakeTheFirstThreeDistinctOwnerColoursInAgendaOrder() {
        let feed = CalendarFeed(events: [
            event("late", "2026-10-27T15:00:00-05:00", "2026-10-27T16:00:00-05:00") { $0.ownerColor = "#00AA00" },
            event("early", "2026-10-27T08:00:00-05:00", "2026-10-27T09:00:00-05:00") { $0.ownerColor = "FF0000" },
            event("same", "2026-10-27T10:00:00-05:00", "2026-10-27T11:00:00-05:00") { $0.ownerColor = "#ff0000" },
            event("none", "2026-10-27T11:00:00-05:00", "2026-10-27T12:00:00-05:00"),
            event("fourth", "2026-10-27T17:00:00-05:00", "2026-10-27T18:00:00-05:00") { $0.ownerColor = "#0000FF" },
            event("bad", "2026-10-28T09:00:00-05:00", "2026-10-28T10:00:00-05:00") { $0.ownerColor = "violet" },
        ])
        let markers = ScheduleAgenda.markers(
            feed: feed,
            zone: chicago,
            milestones: .empty,
            cells: [day(2026, 10, 27), day(2026, 10, 28), day(2026, 10, 29)]
        )
        let busy = markers[day(2026, 10, 27)]
        #expect(busy?.events == 5, "the count stays whole; only the dots stop at three")
        let red = ScheduleCopy.ownerColor("FF0000")
        let green = ScheduleCopy.ownerColor("00AA00")
        #expect(red != nil && green != nil)
        #expect(busy?.eventColors == [red, nil, green])
        #expect(markers[day(2026, 10, 28)]?.eventColors == [nil], "an unusable colour falls back to the accent")
        #expect(markers[day(2026, 10, 29)]?.eventColors == [])
    }

    @Test func eventEndingExactlyAtMidnightAppearsOnlyOnItsStartDay() {
        let feed = CalendarFeed(events: [event("eod", "2026-10-27T22:00:00-05:00", "2026-10-28T00:00:00-05:00")])
        #expect(
            eventIds(ScheduleAgenda.items(feed: feed, zone: chicago, milestones: .empty, on: day(2026, 10, 27)))
                == ["eod"]
        )
        #expect(ScheduleAgenda.items(feed: feed, zone: chicago, milestones: .empty, on: day(2026, 10, 28)).isEmpty)
        let markers = ScheduleAgenda.markers(
            feed: feed,
            zone: chicago,
            milestones: .empty,
            cells: [day(2026, 10, 27), day(2026, 10, 28)]
        )
        #expect(markers[day(2026, 10, 27)]?.events == 1)
        #expect(markers[day(2026, 10, 28)]?.events == 0)
    }

    @Test func eventSpanningSpringForwardHasCorrectClocksAndDay() {
        // 01:30 CST to 03:30 CDT on 8 March 2026 is one real hour.
        let shift = event("spring", "2026-03-08T07:30:00Z", "2026-03-08T08:30:00Z")
        let feed = CalendarFeed(events: [shift])
        #expect(rows(feed, on: day(2026, 3, 8)).first?.subtitle == "1:30 AM – 3:30 AM")
        #expect(rows(feed, on: day(2026, 3, 7)).isEmpty)
        #expect(rows(feed, on: day(2026, 3, 9)).isEmpty)
    }

    @Test func eventAt0030OnTheFallBackDayIsPlacedOnExactlyOneDay() {
        let early = event("early", "2026-11-01T05:30:00Z", "2026-11-01T05:45:00Z")
        let feed = CalendarFeed(events: [early])
        let days = [day(2026, 10, 31), day(2026, 11, 1), day(2026, 11, 2)]
        let placed = days.filter { !rows(feed, on: $0).isEmpty }
        #expect(placed == [day(2026, 11, 1)])
        #expect(rows(feed, on: day(2026, 11, 1)).first?.subtitle == "12:30 AM – 12:45 AM")
    }

    @Test func repeatedFallBackHourIsPlacedOnceAndNamesItsOffset() {
        let first = event("cdt", "2026-11-01T06:30:00Z", "2026-11-01T06:45:00Z")
        let second = event("cst", "2026-11-01T07:30:00Z", "2026-11-01T07:45:00Z")
        let result = rows(CalendarFeed(events: [second, first]), on: day(2026, 11, 1))
        #expect(result.map(\.id) == ["event:cdt", "event:cst"])
        #expect(result[0].subtitle == "1:30 AM CDT – 1:45 AM CDT")
        #expect(result[1].subtitle == "1:30 AM CST – 1:45 AM CST")
        #expect(rows(CalendarFeed(events: [first]), on: day(2026, 10, 31)).isEmpty)
    }

    @Test func overnightShiftAcrossFallBackShowsOnBothDays() {
        // 22:00 CDT on 31 Oct to 06:00 CST on 1 Nov: nine real hours.
        let shift = event("shift", "2026-11-01T03:00:00Z", "2026-11-01T12:00:00Z")
        #expect(shift.end.timeIntervalSince(shift.start) == 9 * 3_600)
        let feed = CalendarFeed(events: [shift])
        #expect(rows(feed, on: day(2026, 10, 31)).first?.subtitle == "10:00 PM – Sun 6:00 AM")
        #expect(rows(feed, on: day(2026, 11, 1)).first?.subtitle == "Sat 10:00 PM – 6:00 AM")
        let markers = ScheduleAgenda.markers(
            feed: feed,
            zone: chicago,
            milestones: .empty,
            cells: SchedulePeriods.cells(.week, containing: day(2026, 11, 1))
        )
        #expect(markers[day(2026, 11, 1)]?.events == 1)
        #expect(markers[day(2026, 11, 2)]?.events == 0)
    }

    @Test func savedZoneWinsOverTheDeviceZone() {
        // 23:30 in Chicago on 27 Oct is already 28 Oct in Tokyo; the schedule follows Chicago.
        let late = event("late", "2026-10-27T23:30:00-05:00", "2026-10-28T00:00:00-05:00")
        let feed = CalendarFeed(events: [late])
        #expect(rows(feed, on: day(2026, 10, 27)).map(\.id) == ["event:late"])
        #expect(rows(feed, on: day(2026, 10, 28)).isEmpty)
        #expect(rows(feed, on: day(2026, 10, 28), zone: Zones.tokyo).map(\.id) == ["event:late"])
    }

    @Test func southernHemisphereSpringForwardEventIsPlacedInSydney() {
        // 01:30 AEST to 03:30 AEDT on 4 Oct 2026.
        let shift = event("syd", "2026-10-03T15:30:00Z", "2026-10-03T16:30:00Z")
        let result = rows(CalendarFeed(events: [shift]), on: day(2026, 10, 4), zone: Zones.sydney)
        #expect(result.first?.subtitle == "1:30 AM – 3:30 AM")
        #expect(rows(CalendarFeed(events: [shift]), on: day(2026, 10, 3), zone: Zones.sydney).isEmpty)
    }

    @Test func southernHemisphereFallBackRepeatsTheHourOnce() {
        let first = event("aedt", "2026-04-04T15:30:00Z", "2026-04-04T15:45:00Z")
        let second = event("aest", "2026-04-04T16:30:00Z", "2026-04-04T16:45:00Z")
        let text = ScheduleText(zone: Zones.sydney, locale: english)
        #expect(text.isRepeatedWallTime(first.start))
        #expect(text.isRepeatedWallTime(second.start))
        #expect(!text.isRepeatedWallTime(instant("2026-04-04T12:00:00Z")))
        let result = rows(CalendarFeed(events: [first, second]), on: day(2026, 4, 5), zone: Zones.sydney)
        #expect(result.count == 2)
        #expect(result[0].subtitle != result[1].subtitle)
        #expect(result.allSatisfy { $0.subtitle.hasPrefix("2:30 AM") })
    }

    @Test func zoneLessStartTimeIsReadAsUtc() {
        let start = instant("2026-10-20T15:00:00")
        #expect(start == instant("2026-10-20T15:00:00Z"))
        let checkin = CalendarEvent(id: "c", title: "Check-in", start: start, end: instant("2026-10-20T15:30:00.48291"))
        #expect(rows(CalendarFeed(events: [checkin]), on: day(2026, 10, 20)).first?.subtitle == "10:00 AM – 10:30 AM")
    }

    @Test func allDayEventsUseLiteralDatesWithAnExclusiveEnd() {
        var training = event("train", "2026-11-05T00:00:00", "2026-11-06T00:00:00")
        training.allDay = .init(start: day(2026, 11, 5), endExclusive: day(2026, 11, 6))
        let feed = CalendarFeed(events: [training])
        for zone in [Zones.chicago, Zones.tokyo, Zones.sydney] {
            #expect(rows(feed, on: day(2026, 11, 5), zone: zone).first?.subtitle == "All day")
            #expect(rows(feed, on: day(2026, 11, 6), zone: zone).isEmpty)
            #expect(rows(feed, on: day(2026, 11, 4), zone: zone).isEmpty)
        }
    }

    @Test func spillDaysOfTheMonthGridGetEventMarkers() {
        let spill = event("spill", "2026-09-28T15:00:00Z", "2026-09-28T16:00:00Z")
        let trailing = event("trail", "2026-11-06T15:00:00Z", "2026-11-06T16:00:00Z")
        let cells = SchedulePeriods.cells(.month, containing: day(2026, 10, 1))
        let markers = ScheduleAgenda.markers(
            feed: CalendarFeed(events: [spill, trailing]),
            zone: chicago,
            milestones: .empty,
            cells: cells
        )
        #expect(markers[day(2026, 9, 28)]?.events == 1)
        #expect(markers[day(2026, 11, 6)]?.events == 1)
        #expect(markers.count == 42)
    }

    @Test func multiDayEventIsCountedOnEveryDayItTouches() {
        var trip = event("trip", "2026-10-26T05:00:00Z", "2026-10-29T05:00:00Z")
        trip.allDay = .init(
            start: day(2026, 10, 26),
            endExclusive: day(2026, 10, 29),
            cancelledDates: [day(2026, 10, 27)]
        )
        let conference = event("conf", "2026-10-26T14:00:00Z", "2026-10-28T20:00:00Z")
        let markers = ScheduleAgenda.markers(
            feed: CalendarFeed(events: [trip, conference]),
            zone: chicago,
            milestones: .empty,
            cells: SchedulePeriods.cells(.week, containing: day(2026, 10, 27))
        )
        #expect(markers[day(2026, 10, 26)]?.events == 2)
        #expect(markers[day(2026, 10, 27)]?.events == 1)
        #expect(markers[day(2026, 10, 28)]?.events == 2)
        #expect(markers[day(2026, 10, 29)]?.events == 0)
    }

    @Test func timeOffAndHolidayCopyMatchTheSpec() {
        var halfDay = CalendarTimeOff(
            id: 7,
            start: instant("2026-10-27T13:00:00Z"),
            end: instant("2026-10-27T17:00:00Z")
        )
        halfDay.requestType = "HALF_DAY_AM"
        halfDay.status = "APPROVED"
        let feed = CalendarFeed(
            timeOff: [halfDay],
            holidays: [Holiday(id: 9, title: nil, start: day(2026, 10, 27), end: day(2026, 10, 27))]
        )
        let result = rows(feed, on: day(2026, 10, 27))
        #expect(result.map(\.title) == ["Holiday", "Time off"])
        #expect(result[0].subtitle == "Company holiday")
        #expect(result[1].subtitle == "Approved · half day am")
    }

    @Test func eventCardsUseTheOwnerColourOrNone() {
        var coloured = event("a", "2026-10-27T15:00:00Z", "2026-10-27T16:00:00Z") { $0.ownerColor = "#7E57C2" }
        coloured.location = "North house"
        let plain = event("b", "2026-10-27T17:00:00Z", "2026-10-27T18:00:00Z") { $0.ownerColor = "purple" }
        let result = rows(CalendarFeed(events: [coloured, plain]), on: day(2026, 10, 27))
        #expect(result[0].ownerColor == RGBColorFixture.purple)
        #expect(result[0].subtitle == "10:00 AM – 11:00 AM · North house")
        #expect(result[1].ownerColor == nil)
    }

    @Test func zeroLengthEventsTouchOnlyTheirStartDay() {
        let span = ScheduleAgenda.daysTouched(
            start: instant("2026-10-28T05:00:00Z"),
            end: instant("2026-10-28T05:00:00Z"),
            zone: chicago
        )
        #expect(span == day(2026, 10, 28)...day(2026, 10, 28))
    }
}
