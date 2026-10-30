import Foundation
import WaiveraAPI
import WaiveraData

/// Time for chat screens. Instants come from the shared UTC parser in the data layer. Inside a
/// conversation or thread, clocks, spoken times and day separators use the employee's saved
/// named zone (`employee(_:)`), the same zone the chat list and the schedule use, so one message
/// never reads two different times (AGENTS.md "Dates and time zones"). Both the clock and the
/// zone are injected so tests can pin them.
struct ChatClock: Sendable {
    let clock: any WaiveraClock
    private let zoneProvider: @Sendable () -> TimeZone

    init(clock: any WaiveraClock = SystemClock(), timeZone: @escaping @Sendable () -> TimeZone = { .current }) {
        self.clock = clock
        zoneProvider = timeZone
    }

    /// The app's clock in the employee's saved zone, falling back to the device zone until a
    /// person is signed in. Read on every use, so a saved-zone change applies at once.
    static func employee(_ data: DataEnvironment) -> ChatClock {
        let calendar = data.calendar
        return ChatClock(clock: data.clock, timeZone: { calendar.scheduleTimeZone().zone })
    }

    var now: Date { clock.now }
    /// Read on every use, so a zone change applies at once.
    var timeZone: TimeZone { zoneProvider() }

    func sleep(seconds: Double) async throws {
        try await clock.sleep(for: .milliseconds(Int(seconds * 1_000)))
    }
}

/// A local calendar day.
struct ChatDay: Hashable, Sendable, Comparable, CustomStringConvertible {
    var year: Int
    var month: Int
    var day: Int

    static func < (lhs: ChatDay, rhs: ChatDay) -> Bool {
        (lhs.year, lhs.month, lhs.day) < (rhs.year, rhs.month, rhs.day)
    }

    var description: String { String(format: "%04d-%02d-%02d", year, month, day) }

    /// Noon on this day in `zone`, for formatting.
    func date(in zone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }
}

/// `formatChatTimestamp` as data, so the copy lives in resources and the rules are testable.
enum RelativeTime: Hashable, Sendable {
    case justNow
    case seconds(Int)
    case minutes(Int)
    case hours(Int)
    case days(Int)
    /// Older than a week: "Oct 20", with the year only when it is not the current year.
    case onDate(ChatDay, showYear: Bool)
}

/// Day separator copy (`messageDateLabel`): "Today", else "Oct 20, 2026".
enum DayLabel: Hashable, Sendable {
    case today
    case onDate(ChatDay)

    static func of(_ day: ChatDay, today: ChatDay) -> DayLabel { day == today ? .today : .onDate(day) }
}

enum ChatTime {
    private static let justNowSeconds = 10.0
    private static let minute = 60.0
    private static let hour = 3_600.0
    private static let dayLength = 86_400.0
    private static let week = 7 * dayLength

    static func relative(_ value: Date, now: Date, zone: TimeZone) -> RelativeTime {
        let seconds = now.timeIntervalSince(value).rounded(.down)
        switch seconds {
        case ..<justNowSeconds: return .justNow
        case ..<minute: return .seconds(Int(seconds))
        case ..<hour: return .minutes(Int(seconds / minute))
        case ..<dayLength: return .hours(Int(seconds / hour))
        case ..<week: return .days(Int(seconds / dayLength))
        default:
            let date = day(value, zone: zone)
            return .onDate(date, showYear: date.year != day(now, zone: zone).year)
        }
    }

    /// The local calendar day of `value`, used for grouping and day separators.
    static func day(_ value: Date, zone: TimeZone) -> ChatDay {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let parts = calendar.dateComponents([.year, .month, .day], from: value)
        return ChatDay(year: parts.year ?? 0, month: parts.month ?? 0, day: parts.day ?? 0)
    }

    /// 12-hour clock in `zone` (11 §39), for call logs and a row's accessibility label.
    static func clock(_ value: Date, zone: TimeZone, locale: Locale = .current) -> String {
        formatter("h:mm a", zone: zone, locale: locale).string(from: value)
    }

    /// "Oct 20" or "Oct 20, 2025".
    static func shortDate(_ day: ChatDay, showYear: Bool, locale: Locale = .current) -> String {
        let zone = TimeZone(identifier: "UTC") ?? .current
        guard let date = day.date(in: zone) else { return day.description }
        return formatter(showYear ? "MMM d, yyyy" : "MMM d", zone: zone, locale: locale).string(from: date)
    }

    private static func formatter(_ format: String, zone: TimeZone, locale: Locale) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = zone
        formatter.dateFormat = format
        return formatter
    }
}
