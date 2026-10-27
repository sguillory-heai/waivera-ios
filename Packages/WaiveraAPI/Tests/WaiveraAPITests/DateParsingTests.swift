import Foundation
import Testing

@testable import WaiveraAPI

struct WaiveraInstantTests {
    @Test(arguments: [
        ("2026-10-20T14:32:11", 0.0),
        ("2026-10-20T14:32:11.4", 0.4),
        ("2026-10-20T14:32:11.48", 0.48),
        ("2026-10-20T14:32:11.482", 0.482),
        ("2026-10-20T14:32:11.482913", 0.482913),
        ("2026-10-20T14:32:11.4829130", 0.482913),
    ])
    func zoneLessTimestampsAreUTCWithAnyFractionLength(raw: String, fraction: Double) throws {
        let date = try #require(WaiveraInstant.parse(raw))
        #expect(abs(date.timeIntervalSince1970 - utc(2026, 10, 20, 14, 32, 11 + fraction).timeIntervalSince1970) < 1e-5)
    }

    @Test func explicitZoneAndOffsetsAreNotConvertedTwice() throws {
        let expected = utc(2026, 10, 20, 14, 40, 2.118374)
        for raw in [
            "2026-10-20T14:40:02.118374Z", "2026-10-20T09:40:02.118374-05:00", "2026-10-20T20:10:02.118374+0530",
        ] {
            let date = try #require(WaiveraInstant.parse(raw))
            #expect(abs(date.timeIntervalSince(expected)) < 1e-5, "\(raw)")
        }
    }

    @Test func zoneLessAndZonedFormsOfTheSameInstantAreEqual() throws {
        let bare = try #require(WaiveraInstant.parse("2026-10-20T14:50:00.0000000"))
        let zoned = try #require(WaiveraInstant.parse("2026-10-20T14:50:00.0000000Z"))
        #expect(bare == zoned)
    }

    @Test(arguments: ["", "2026-10-20", "2026-13-01T00:00:00", "2026-02-30T00:00:00", "20261020T143211", "garbage"])
    func rejectsMalformedInput(raw: String) {
        #expect(WaiveraInstant.parse(raw) == nil)
    }

    @Test func acceptsLeapDay() throws {
        #expect(WaiveraInstant.parse("2028-02-29T12:00:00") == utc(2028, 2, 29, 12))
        #expect(WaiveraInstant.parse("2026-02-29T12:00:00") == nil)
    }

    @Test func formatRoundTripsThroughParse() throws {
        let date = utc(2026, 11, 1, 6, 30, 15.25)
        #expect(WaiveraInstant.format(date) == "2026-11-01T06:30:15.250Z")
        #expect(WaiveraInstant.parse(WaiveraInstant.format(date)) == date)
        #expect(WaiveraInstant.format(utc(1969, 12, 31, 23, 59, 59.5)) == "1969-12-31T23:59:59.500Z")
    }

    @Test func decoderUsesTheSharedParserForZoneLessDates() throws {
        struct Payload: Decodable { var createDate: Date }
        let json = Data(#"{"createDate":"2026-10-20T14:32:11.482913"}"#.utf8)
        let payload = try WaiveraJSON.decoder().decode(Payload.self, from: json)
        #expect(abs(payload.createDate.timeIntervalSince(utc(2026, 10, 20, 14, 32, 11.482913))) < 1e-5)
    }
}

struct CalendarDateTests {
    let chicago = TimeZone(identifier: "America/Chicago")

    @Test func parsesDateOnlyAndTheDatePartOfMidnightDateTimes() throws {
        #expect(CalendarDate(parsing: "2026-10-20") == CalendarDate(year: 2026, month: 10, day: 20))
        // Birthdays arrive as DateTime; only the components are kept, so no day drift.
        #expect(CalendarDate(parsing: "1991-06-14T00:00:00") == CalendarDate(year: 1991, month: 6, day: 14))
        #expect(CalendarDate(parsing: "2026-02-29") == nil)
    }

    @Test func springForwardDayInChicagoIs23Hours() throws {
        let zone = try #require(chicago)
        let day = try #require(CalendarDate(year: 2026, month: 3, day: 8))
        let interval = day.interval(in: zone)
        #expect(interval.duration == 23 * 3_600)
        #expect(interval.start == utc(2026, 3, 8, 6))
        #expect(interval.end == utc(2026, 3, 9, 5))
    }

    @Test func fallBackDayInChicagoIs25Hours() throws {
        let zone = try #require(chicago)
        let day = try #require(CalendarDate(year: 2026, month: 11, day: 1))
        let interval = day.interval(in: zone)
        #expect(interval.duration == 25 * 3_600)
        #expect(interval.start == utc(2026, 11, 1, 5))
        #expect(interval.end == utc(2026, 11, 2, 6))
    }

    @Test func bothRepeatedHourInstantsFallOnTheFallBackDate() throws {
        let zone = try #require(chicago)
        // 01:30 CDT (06:30Z) and 01:30 CST (07:30Z) are both on 1 Nov in Chicago.
        #expect(CalendarDate(utc(2026, 11, 1, 6, 30), in: zone) == CalendarDate(year: 2026, month: 11, day: 1))
        #expect(CalendarDate(utc(2026, 11, 1, 7, 30), in: zone) == CalendarDate(year: 2026, month: 11, day: 1))
    }

    @Test func utcMidnightIsThePreviousLocalDayWestOfUTC() throws {
        let zone = try #require(chicago)
        #expect(CalendarDate(utc(2026, 10, 21), in: zone) == CalendarDate(year: 2026, month: 10, day: 20))
        let tokyo = try #require(TimeZone(identifier: "Asia/Tokyo"))
        #expect(CalendarDate(utc(2026, 10, 20, 15), in: tokyo) == CalendarDate(year: 2026, month: 10, day: 21))
        let kolkata = try #require(TimeZone(identifier: "Asia/Kolkata"))
        #expect(CalendarDate(utc(2026, 10, 20, 18, 30), in: kolkata) == CalendarDate(year: 2026, month: 10, day: 21))
    }

    @Test func weeksStartOnSunday() throws {
        let wednesday = try #require(CalendarDate(year: 2026, month: 10, day: 21))
        #expect(wednesday.weekday == 4)
        #expect(wednesday.startOfWeek == CalendarDate(year: 2026, month: 10, day: 18))
        let sunday = try #require(CalendarDate(year: 2026, month: 11, day: 1))
        #expect(sunday.startOfWeek == sunday)
    }

    @Test func monthAndYearRollover() throws {
        let date = try #require(CalendarDate(year: 2026, month: 12, day: 31))
        #expect(date.adding(days: 1) == CalendarDate(year: 2027, month: 1, day: 1))
        #expect(date.addingMonths(2) == CalendarDate(year: 2027, month: 2, day: 28))
        let leap = try #require(CalendarDate(year: 2028, month: 1, day: 31))
        #expect(leap.addingMonths(1) == CalendarDate(year: 2028, month: 2, day: 29))
        #expect(leap.addingMonths(-13) == CalendarDate(year: 2026, month: 12, day: 31))
    }

    @Test func dateOnlyRoundTripsThroughJSON() throws {
        let date = try #require(CalendarDate(year: 2026, month: 11, day: 26))
        let data = try WaiveraJSON.encoder().encode([date])
        #expect(String(decoding: data, as: UTF8.self) == #"["2026-11-26"]"#)
        #expect(try WaiveraJSON.decoder().decode([CalendarDate].self, from: data) == [date])
    }
}
