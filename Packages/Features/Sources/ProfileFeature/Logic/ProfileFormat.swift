import Foundation
import WaiveraAPI

/// Date formatting for the profile screens.
///
/// Birthdays and hire dates are `CalendarDate` values. They are formatted from their components
/// only (the formatter runs in UTC over UTC midnight of that date), so they never move by a day
/// on any device zone. The Expo app parsed them as UTC instants and rendered them in the device
/// zone, which showed 1 April for a 2 April birthday west of UTC (11-pitfalls #30).
public enum ProfileFormat {
    private static let utc = TimeZone(identifier: "UTC") ?? TimeZone(secondsFromGMT: 0) ?? .current

    private static func gregorian(_ locale: Locale) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        calendar.locale = locale
        return calendar
    }

    private static func utcMidnight(_ date: CalendarDate) -> Date {
        Date(timeIntervalSince1970: Double(date.daysSinceEpoch) * 86_400)
    }

    /// "Mar 14, 2022".
    public static func date(_ value: CalendarDate, locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(
            date: .abbreviated,
            time: .omitted,
            locale: locale,
            calendar: gregorian(locale),
            timeZone: utc
        )
        return utcMidnight(value).formatted(style)
    }

    /// "Apr 2": birthdays never show the year.
    public static func birthday(_ value: CalendarDate, locale: Locale = .autoupdatingCurrent) -> String {
        let style = Date.FormatStyle(locale: locale, calendar: gregorian(locale), timeZone: utc)
            .month(.abbreviated)
            .day()
        return utcMidnight(value).formatted(style)
    }

    /// An instant (a file's upload time) as a date in the employee's saved `zone`.
    public static func date(of instant: Date, in zone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        date(CalendarDate(instant, in: zone), locale: locale)
    }

    /// "Nov 3, 2026" for one day, "Nov 3, 2026 – Nov 5, 2026" for a range; `nil` without dates.
    public static func dateRange(
        start: CalendarDate?,
        end: CalendarDate?,
        locale: Locale = .autoupdatingCurrent
    ) -> String? {
        guard let first = start ?? end else { return nil }
        guard let start, let end, end != start else { return date(first, locale: locale) }
        return "\(date(start, locale: locale)) – \(date(end, locale: locale))"
    }

    /// "Central Time" for America/Chicago; the identifier when the system has no name for it.
    public static func zoneName(_ zone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
        guard let name = zone.localizedName(for: .generic, locale: locale), !name.isEmpty else {
            return zone.identifier
        }
        return name
    }

    /// Day counts such as 12 or 12.5, without trailing zeros.
    public static func days(_ value: Double, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(locale))
    }
}
