import Foundation
import WaiveraAPI

/// Relative time rules for Today. Every calculation takes the zone explicitly (the employee's
/// saved zone), never the device zone, and measures durations between instants so DST days
/// count real minutes, not wall-clock minutes.
enum TimeLabels {
    static let relativeHours = 6

    static func upcoming(start: Date, end: Date?, now: Date, zone: TimeZone) -> UpcomingLabel {
        guard start > now else {
            return .now(until: end.map { ClockTime($0, in: zone) })
        }
        let minutes = Int((start.timeIntervalSince(now) / 60).rounded(.up))
        let today = CalendarDate(now, in: zone)
        let day = CalendarDate(start, in: zone)
        let clock = ClockTime(start, in: zone)
        switch minutes {
        case ..<60: return .inMinutes(minutes)
        case ..<(relativeHours * 60): return .inHours(minutes / 60, minutes: minutes % 60)
        default:
            if day == today { return .todayAt(clock) }
            if day == today.adding(days: 1) { return .tomorrowAt(clock) }
            return .onDayAt(day, clock)
        }
    }

    /// An all-day item that covers `today` reads "All day today", whatever day it started.
    static func allDay(start: CalendarDate, endExclusive: CalendarDate?, today: CalendarDate) -> UpcomingLabel {
        let end = endExclusive.flatMap { $0 > start ? $0 : nil } ?? start.adding(days: 1)
        if today >= start && today < end { return .allDayToday }
        if start == today.adding(days: 1) { return .allDayTomorrow }
        return .allDayOn(start)
    }

    static func past(_ date: Date, now: Date, zone: TimeZone) -> PastLabel {
        let elapsed = now.timeIntervalSince(date)
        if elapsed < 60 { return .justNow }
        if elapsed < 3_600 { return .minutesAgo(Int(elapsed / 60)) }
        let today = CalendarDate(now, in: zone)
        let day = CalendarDate(date, in: zone)
        if day == today { return .todayAt(ClockTime(date, in: zone)) }
        if day == today.adding(days: -1) { return .yesterday }
        return .onDate(day)
    }
}
