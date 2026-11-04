import Foundation
import WaiveraAPI
import WaiveraData

/// How a due date reads next to today. Due dates are literal calendar dates and "today" is the
/// employee's saved-zone day, so a task due Friday reads "Due Fri, Nov 6" wherever the phone is.
enum DueText: Hashable, Sendable {
    case none
    case today
    case tomorrow
    case on(String)
    case yesterday
    case wasOn(String)

    var overdue: Bool {
        switch self {
        case .yesterday, .wasOn: true
        default: false
        }
    }

    var text: String {
        switch self {
        case .none: TasksStrings.text("tasks.due.none")
        case .today: TasksStrings.text("tasks.due.today")
        case .tomorrow: TasksStrings.text("tasks.due.tomorrow")
        case .on(let label): TasksStrings.format("tasks.due.on", label)
        case .yesterday: TasksStrings.text("tasks.due.yesterday")
        case .wasOn(let label): TasksStrings.format("tasks.due.wasOn", label)
        }
    }
}

/// A wall-clock moment in the employee's zone: "Today, 2:30 PM". Clock times are 12-hour.
struct TaskMoment: Hashable, Sendable {
    enum RelativeDay: Hashable, Sendable { case today, yesterday, other }

    var relativeDay: RelativeDay
    var day: String
    var time: String

    var text: String {
        switch relativeDay {
        case .today: TasksStrings.format("tasks.moment.today", time)
        case .yesterday: TasksStrings.format("tasks.moment.yesterday", time)
        case .other: TasksStrings.format("tasks.moment.day", day, time)
        }
    }
}

enum TaskFormat {
    static func due(_ due: CalendarDate?, today: CalendarDate) -> DueText {
        guard let due else { return .none }
        if due == today { return .today }
        if due == today.adding(days: 1) { return .tomorrow }
        if due == today.adding(days: -1) { return .yesterday }
        if due < today { return .wasOn(shortDate(due, today: today)) }
        return .on(date(due, today: today))
    }

    /// "Fri, Nov 6", with the year ("Nov 6, 2027") when it is not this one.
    static func date(_ date: CalendarDate, today: CalendarDate) -> String {
        format(date, template: date.year == today.year ? "EEEMMMd" : "MMMdyyyy")
    }

    /// A short date for a line of facts: "Nov 20", with the year when it is not this one.
    static func shortDate(_ date: CalendarDate, today: CalendarDate) -> String {
        format(date, template: date.year == today.year ? "MMMd" : "MMMdyyyy")
    }

    /// The date tile's month, "Nov".
    static func tileMonth(_ date: CalendarDate) -> String { format(date, template: "MMM") }

    static func moment(_ at: Date, zone: TimeZone, today: CalendarDate) -> TaskMoment {
        let day = CalendarDate(at, in: zone)
        let relative: TaskMoment.RelativeDay =
            switch day.days(until: today) {
            case 0: .today
            case 1: .yesterday
            default: .other
            }
        let dayLabel = day.year == today.year ? format(day, template: "EEEMMMd") : format(day, template: "MMMdyyyy")
        return TaskMoment(relativeDay: relative, day: dayLabel, time: time(at, zone: zone))
    }

    /// "2:30 PM" in the employee's zone, always 12-hour.
    static func time(_ at: Date, zone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = zone
        formatter.dateFormat = "h:mm a"
        formatter.amSymbol = "AM"
        formatter.pmSymbol = "PM"
        return formatter.string(from: at)
    }

    /// "1 hr 15 min", "45 min", "2 hr".
    static func duration(_ minutes: Int) -> String {
        let hours = minutes / 60
        let rest = minutes % 60
        let hourText = TasksStrings.plural("tasks.duration.hours", hours)
        let minuteText = TasksStrings.plural("tasks.duration.minutes", rest)
        if hours == 0 { return minuteText }
        if rest == 0 { return hourText }
        return TasksStrings.format("tasks.duration.both", hourText, minuteText)
    }

    static func stateLabel(_ state: TaskState) -> String {
        switch state {
        case .notStarted: TasksStrings.text("tasks.state.notStarted")
        case .inProgress: TasksStrings.text("tasks.state.inProgress")
        case .inReview: TasksStrings.text("tasks.state.inReview")
        case .completed: TasksStrings.text("tasks.state.completed")
        case .closed: TasksStrings.text("tasks.state.closed")
        case .other(let name):
            name.isEmpty
                ? TasksStrings.text("tasks.state.notStarted")
                : name.prefix(1).uppercased() + name.dropFirst().lowercased()
        }
    }

    /// Calendar dates are formatted at noon UTC, so no zone can move them to another day.
    private static func format(_ date: CalendarDate, template: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: Date(timeIntervalSince1970: Double(date.daysSinceEpoch) * 86_400 + 43_200))
    }
}
