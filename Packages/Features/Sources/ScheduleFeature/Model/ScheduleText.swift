import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

/// Formats schedule dates and times in one zone. Built once per zone and locale and reused, so
/// no formatter is created while a view renders. Clocks are 12-hour (11-pitfalls §39).
///
/// Literal dates are formatted through a Gregorian `Calendar` set to the same zone, at local
/// noon, so a date never drifts across a DST midnight.
final class ScheduleText {
    let zone: TimeZone
    let locale: Locale
    let calendar: Calendar
    private var formatters: [String: DateFormatter] = [:]

    init(zone: TimeZone, locale: Locale = .autoupdatingCurrent) {
        self.zone = zone
        self.locale = locale
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        calendar.locale = locale
        calendar.firstWeekday = 1
        self.calendar = calendar
    }

    // MARK: Instants

    /// "10:00 PM". A wall time that happens twice on a fall-back day also names its zone
    /// ("1:30 AM CDT" and "1:30 AM CST"), so the two are never confused.
    func clock(_ date: Date) -> String {
        format(date, pattern: isRepeatedWallTime(date) ? "h:mm a zzz" : "h:mm a")
    }

    /// "Sun, Nov 1, 10:00 PM" (07 §5 event detail), with the year when it is not `currentYear`.
    func dateTime(_ date: Date, currentYear: Int) -> String {
        let day = CalendarDate(date, in: zone)
        let pattern = day.year == currentYear ? "EEE, MMM d" : "EEE, MMM d, yyyy"
        return ScheduleStrings.format("schedule.dateTime", format(date, pattern: pattern), clock(date))
    }

    /// True when the local wall-clock reading of `date` also belongs to another instant, which
    /// only happens in the repeated hour after a fall-back transition.
    func isRepeatedWallTime(_ date: Date) -> Bool {
        let offset = zone.secondsFromGMT(for: date)
        let neighbours = Set([-7_200.0, 7_200.0].map { zone.secondsFromGMT(for: date.addingTimeInterval($0)) })
        for other in neighbours where other != offset {
            let twin = date.addingTimeInterval(TimeInterval(offset - other))
            if zone.secondsFromGMT(for: twin) == other { return true }
        }
        return false
    }

    // MARK: Literal dates

    /// "October 2026".
    func monthYear(_ date: CalendarDate) -> String { format(date, pattern: "MMMM yyyy") }
    /// "Tue, October 27".
    func weekdayMonthDay(_ date: CalendarDate) -> String { format(date, pattern: "EEE, MMMM d") }
    /// "October 25".
    func monthDay(_ date: CalendarDate) -> String { format(date, pattern: "MMMM d") }
    /// "Sunday, November 1": the agenda heading and a cell's spoken name.
    func fullDay(_ date: CalendarDate) -> String { format(date, pattern: "EEEE, MMMM d") }
    /// "Sun, Nov 1", with the year when it is not `currentYear`.
    func shortDay(_ date: CalendarDate, currentYear: Int) -> String {
        format(date, pattern: date.year == currentYear ? "EEE, MMM d" : "EEE, MMM d, yyyy")
    }
    func dayNumber(_ date: CalendarDate) -> String { format(date, pattern: "d") }
    func year(_ date: CalendarDate) -> String { format(date, pattern: "yyyy") }
    func weekdayShort(_ date: CalendarDate) -> String { format(date, pattern: "EEE") }

    /// "Sun" … "Sat": the grid always starts on Sunday.
    var weekdayHeaders: [String] {
        let formatter = formatter(for: "EEE")
        let symbols = formatter.shortWeekdaySymbols
        return symbols.count == 7 ? symbols : ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    }

    func title(_ title: PeriodTitle) -> String {
        switch title {
        case .month(let date):
            monthYear(date)
        case .day(let date):
            weekdayMonthDay(date)
        case .weekInMonth(let start, let end):
            ScheduleStrings.format("schedule.period.weekInMonth", monthDay(start), dayNumber(end), year(end))
        case .weekAcrossMonths(let start, let end):
            ScheduleStrings.format("schedule.period.weekAcrossMonths", monthDay(start), monthDay(end))
        }
    }

    /// "Central Time" for America/Chicago; the identifier when the system has no name for it.
    func zoneName() -> String {
        zone.localizedName(for: .generic, locale: locale) ?? zone.identifier
    }

    /// Local noon of `date` in the zone: always exists and is unambiguous.
    func noon(_ date: CalendarDate) -> Date {
        calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day, hour: 12))
            ?? date.startInstant(in: zone)
    }

    private func format(_ date: CalendarDate, pattern: String) -> String {
        format(noon(date), pattern: pattern)
    }

    private func format(_ date: Date, pattern: String) -> String {
        formatter(for: pattern).string(from: date)
    }

    private func formatter(for pattern: String) -> DateFormatter {
        if let cached = formatters[pattern] { return cached }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = zone
        formatter.locale = locale
        formatter.dateFormat = pattern
        formatters[pattern] = formatter
        return formatter
    }
}

/// Text rules that do not depend on a zone.
enum ScheduleCopy {
    /// "APPROVED" → "Approved", "CANCELLATION_PENDING" → "Cancellation pending".
    static func sentenceCase(_ raw: String?) -> String? {
        guard let words = raw?.trimmingCharacters(in: .whitespaces), !words.isEmpty else { return nil }
        let lowered = words.replacingOccurrences(of: "_", with: " ").lowercased()
        return lowered.prefix(1).uppercased() + lowered.dropFirst()
    }

    /// "HALF_DAY_AM" → "half day am" (07 §3 time-off subtitle); a missing type reads "full day".
    static func requestTypeLabel(_ raw: String?) -> String {
        let value = raw?.trimmingCharacters(in: .whitespaces) ?? ""
        return (value.isEmpty ? "FULL_DAY" : value).replacingOccurrences(of: "_", with: " ").lowercased()
    }

    /// An owner colour as the server sends it ("#7E57C2", "7E57C2" or "#FF7E57C2", ARGB). Anything
    /// else returns nil and the card uses the accent token.
    static func ownerColor(_ raw: String?) -> RGBColor? {
        guard var hex = raw?.trimmingCharacters(in: .whitespaces) else { return nil }
        if hex.hasPrefix("#") { hex.removeFirst() }
        guard hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit), let value = UInt64(hex, radix: 16)
        else { return nil }
        if hex.count == 6 { return RGBColor(hex: UInt32(value)) }
        let alpha = Double((value >> 24) & 0xFF) / 255
        return RGBColor(hex: UInt32(value & 0xFF_FFFF), alpha: alpha)
    }
}
