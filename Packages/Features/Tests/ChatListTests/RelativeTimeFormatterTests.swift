import Foundation
import Testing

@testable import ChatFeature

/// 02 §4 "Timestamp", in the employee's saved zone, across the 1 Nov 2026 DST change.
@MainActor
struct RelativeTimeFormatterTests {
    let formatter = RelativeTimeFormatter(text: EnglishText(), locale: Locale(identifier: "en_US"))
    let chicago = TimeZone(identifier: "America/Chicago") ?? .gmt
    /// 2026-11-01 23:30 CST (05:30 UTC on 2 Nov), the end of the 25-hour day.
    let lateOnDSTDay = Date(timeIntervalSince1970: 1_793_597_400)

    @Test("No date is blank; under a minute is Now; under an hour counts minutes")
    func shortLabels() {
        #expect(formatter.label(for: nil, now: lateOnDSTDay, timeZone: chicago) == "")
        #expect(
            formatter.label(for: lateOnDSTDay.addingTimeInterval(-30), now: lateOnDSTDay, timeZone: chicago) == "Now"
        )
        #expect(
            formatter.label(for: lateOnDSTDay.addingTimeInterval(20), now: lateOnDSTDay, timeZone: chicago) == "Now"
        )
        #expect(
            formatter.label(for: lateOnDSTDay.addingTimeInterval(-59 * 60), now: lateOnDSTDay, timeZone: chicago)
                == "59m"
        )
    }

    @Test("Earlier the same day uses a 12-hour clock, even across the repeated hour")
    func sameDayAcrossDST() {
        // 00:30 CDT on 1 Nov (05:30 UTC on 1 Nov): 24 hours earlier in UTC, same local day.
        let earlyCDT = lateOnDSTDay.addingTimeInterval(-24 * 3_600)
        #expect(formatter.label(for: earlyCDT, now: lateOnDSTDay, timeZone: chicago) == "12:30 AM")
    }

    @Test("The previous calendar day is Yesterday across DST; older dates are short dates")
    func yesterdayAndOlder() {
        // 23:45 CDT on 31 Oct (04:45 UTC on 1 Nov).
        let lastNight = Date(timeIntervalSince1970: 1_793_508_300)
        #expect(formatter.label(for: lastNight, now: lateOnDSTDay, timeZone: chicago) == "Yesterday")
        let october20 = Date(timeIntervalSince1970: 1_792_506_731)
        #expect(formatter.label(for: october20, now: lateOnDSTDay, timeZone: chicago) == "Oct 20")
    }

    @Test("Days are taken in the saved zone, not the device zone")
    func savedZoneDecidesTheDay() {
        // 23:30 UTC on 1 Nov is 17:30 in Chicago, the same day; in UTC "now" is already 2 Nov.
        let message = lateOnDSTDay.addingTimeInterval(-6 * 3_600)
        let utc = TimeZone(identifier: "UTC") ?? .gmt
        #expect(formatter.label(for: message, now: lateOnDSTDay, timeZone: chicago) == "5:30 PM")
        #expect(formatter.label(for: message, now: lateOnDSTDay, timeZone: utc) == "Yesterday")
    }
}
