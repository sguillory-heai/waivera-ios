import Foundation
import WaiveraAPI

/// Turns Today's semantic time labels into text. Clock times are always 12-hour (11-pitfalls
/// #39). Labels already hold wall-clock values in the employee's zone, so formatting runs in
/// UTC and never consults the device zone.
struct TodayFormatter {
    private let time: DateFormatter
    private let day: DateFormatter
    private let longDay: DateFormatter

    init(locale: Locale = .autoupdatingCurrent) {
        time = Self.formatter("h:mm a", locale: locale)
        day = Self.formatter("EEE, MMM d", locale: locale)
        longDay = Self.formatter("EEEE, MMMM d", locale: locale)
    }

    private static func formatter(_ format: String, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    func time(_ value: ClockTime) -> String {
        time.string(from: Date(timeIntervalSince1970: TimeInterval(value.hour * 3_600 + value.minute * 60)))
    }

    func day(_ value: CalendarDate) -> String {
        day.string(from: Self.utcStart(value))
    }

    func longDay(_ value: CalendarDate) -> String {
        longDay.string(from: Self.utcStart(value))
    }

    private static func utcStart(_ value: CalendarDate) -> Date {
        Date(timeIntervalSince1970: TimeInterval(value.daysSinceEpoch) * 86_400)
    }

    // MARK: Upcoming

    // swiftlint:disable:next cyclomatic_complexity
    func upcoming(_ label: UpcomingLabel) -> String {
        switch label {
        case .now(let until):
            guard let until else { return TodayStrings.text("today.upcoming.now") }
            return TodayStrings.format("today.upcoming.nowUntil", time(until))
        case .inMinutes(let minutes):
            guard minutes > 0 else { return TodayStrings.text("today.upcoming.startingNow") }
            return TodayStrings.format("today.upcoming.inMinutes", String(minutes))
        case .inHours(let hours, let minutes):
            guard minutes > 0 else { return TodayStrings.format("today.upcoming.inHours", String(hours)) }
            return TodayStrings.format("today.upcoming.inHoursMinutes", String(hours), String(minutes))
        case .todayAt(let clock):
            return TodayStrings.format("today.upcoming.todayAt", time(clock))
        case .tomorrowAt(let clock):
            return TodayStrings.format("today.upcoming.tomorrowAt", time(clock))
        case .onDayAt(let date, let clock):
            return TodayStrings.format("today.upcoming.dayAt", day(date), time(clock))
        case .allDayToday:
            return TodayStrings.text("today.upcoming.allDayToday")
        case .allDayTomorrow:
            return TodayStrings.text("today.upcoming.allDayTomorrow")
        case .allDayOn(let date):
            return TodayStrings.format("today.upcoming.allDayOn", day(date))
        }
    }

    /// "11:00 AM – 12:00 PM", with "next day" for overnight items; `nil` for all-day items.
    func range(_ item: NextUpItem) -> String? {
        guard let start = item.start else { return nil }
        guard let end = item.end else { return time(start) }
        let key = item.endsOnLaterDay ? "today.range.nextDay" : "today.range"
        return TodayStrings.format(key, time(start), time(end))
    }

    // MARK: Past

    /// The compact label rows show ("Now", "5m", "9:12 AM", "Yesterday", "Sat, Oct 31").
    func past(_ label: PastLabel) -> String {
        switch label {
        case .justNow: TodayStrings.text("today.past.now")
        case .minutesAgo(let minutes): TodayStrings.format("today.past.minutes", String(minutes))
        case .todayAt(let clock): time(clock)
        case .yesterday: TodayStrings.text("today.past.yesterday")
        case .onDate(let date): day(date)
        }
    }

    /// The spoken form: "5 minutes ago" instead of "5m".
    func pastSpoken(_ label: PastLabel) -> String {
        guard case .minutesAgo(let minutes) = label else { return past(label) }
        let key = minutes == 1 ? "today.past.minutesSpoken.one" : "today.past.minutesSpoken.other"
        return TodayStrings.format(key, String(minutes))
    }

    /// The phrase used after "Updated": "12 min ago", "at 9:12 AM", "yesterday", "on Sat, Oct 31".
    func since(_ label: PastLabel) -> String {
        switch label {
        case .justNow: TodayStrings.text("today.since.justNow")
        case .minutesAgo(let minutes): TodayStrings.format("today.since.minutes", String(minutes))
        case .todayAt(let clock): TodayStrings.format("today.since.at", time(clock))
        case .yesterday: TodayStrings.text("today.since.yesterday")
        case .onDate(let date): TodayStrings.format("today.since.on", day(date))
        }
    }

    func quiet(_ status: QuietStatus) -> String {
        switch status {
        case .offline(let since?): TodayStrings.format("today.quiet.offlineSince", self.since(since))
        case .offline(nil): TodayStrings.text("today.quiet.offline")
        case .stale(let since): TodayStrings.format("today.quiet.stale", self.since(since))
        }
    }
}
