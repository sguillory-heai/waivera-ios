import Foundation
import WaiveraAPI
import WaiveraData

/// When an event happens relative to one agenda day, already placed in the schedule zone.
public enum EventTiming: Sendable, Hashable {
    /// Literal dates, never shifted by a zone. `endInclusive == start` for a one-day event.
    case allDay(start: CalendarDate, endInclusive: CalendarDate)
    /// A timed span. The flags say whether it continues from the previous day or into the next,
    /// so an overnight shift reads correctly on both days.
    case timed(start: Date, end: Date, startsBeforeDay: Bool, endsAfterDay: Bool)
}

/// One card in the day agenda.
public enum AgendaItem: Sendable, Hashable, Identifiable {
    case celebration(ScheduleCelebration)
    case holiday(Holiday)
    case timeOff(CalendarTimeOff, EventTiming)
    case event(CalendarEvent, EventTiming)

    public var id: String {
        switch self {
        case .celebration(let celebration): "celebration:\(celebration.userId)"
        case .holiday(let holiday): "holiday:\(holiday.id)"
        case .timeOff(let entry, _): "timeoff:\(entry.id)"
        case .event(let event, _): "event:\(event.id)"
        }
    }
}

/// What a grid cell marks. Counts rather than a bare dot, so the cell can say
/// "2 events, 1 celebration" and the state is never colour-only.
public struct DayMarker: Sendable, Hashable {
    public var events = 0
    public var celebrations = 0

    public init(events: Int = 0, celebrations: Int = 0) {
        self.events = events
        self.celebrations = celebrations
    }

    public var isEmpty: Bool { events == 0 && celebrations == 0 }
}

/// Builds the day agenda and the grid markers from a feed. Every day boundary is in the schedule
/// zone; timed events are half-open, so one ending exactly at local midnight does not touch the
/// next day (fixes the Expo inclusive-end test).
public enum ScheduleAgenda {
    /// Celebrations, then holidays, then time off, then events (all-day first, then by start
    /// instant, never by string).
    public static func items(
        feed: CalendarFeed,
        zone: TimeZone,
        milestones: MilestoneCalendar,
        on date: CalendarDate
    ) -> [AgendaItem] {
        let celebrations = milestones.celebrations(on: date).map(AgendaItem.celebration)
        let holidays = feed.holidays.filter { $0.occurs(on: date) }
            .sorted { ($0.title ?? "", $0.id) < ($1.title ?? "", $1.id) }
            .map(AgendaItem.holiday)
        let timeOff = feed.timeOff.filter { $0.occurs(on: date, in: zone) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .map { AgendaItem.timeOff($0, timed(start: $0.start, end: $0.end, zone: zone, day: date)) }
        let events = eventsOn(feed.events, zone: zone, date: date)
            .map { AgendaItem.event($0, timing(of: $0, zone: zone, day: date)) }
        return celebrations + holidays + timeOff + events
    }

    public static func eventsOn(_ events: [CalendarEvent], zone: TimeZone, date: CalendarDate) -> [CalendarEvent] {
        events.filter { $0.occurs(on: date, in: zone) }
            .sorted { lhs, rhs in
                let left = (lhs.isAllDay ? 0 : 1, lhs.allDay?.start.daysSinceEpoch ?? 0)
                let right = (rhs.isAllDay ? 0 : 1, rhs.allDay?.start.daysSinceEpoch ?? 0)
                if left != right { return left < right }
                if lhs.start != rhs.start { return lhs.start < rhs.start }
                return (lhs.title ?? "", lhs.id) < (rhs.title ?? "", rhs.id)
            }
    }

    /// Event and celebration counts for each of `cells`, walking each event's days once instead
    /// of filtering the whole feed per cell.
    public static func markers(
        feed: CalendarFeed,
        zone: TimeZone,
        milestones: MilestoneCalendar,
        cells: [CalendarDate]
    ) -> [CalendarDate: DayMarker] {
        guard let first = cells.first, let last = cells.last else { return [:] }
        var events: [CalendarDate: Int] = [:]
        for event in feed.events {
            let span = days(of: event, zone: zone)
            var day = max(span.lowerBound, first)
            let end = min(span.upperBound, last)
            while day <= end {
                if event.allDay?.contains(day) ?? true {
                    events[day, default: 0] += 1
                }
                day = day.adding(days: 1)
            }
        }
        var markers: [CalendarDate: DayMarker] = [:]
        for cell in cells {
            markers[cell] = DayMarker(events: events[cell] ?? 0, celebrations: milestones.count(on: cell))
        }
        return markers
    }

    public static func timing(of event: CalendarEvent, zone: TimeZone, day: CalendarDate) -> EventTiming {
        if let allDay = event.allDay {
            let endInclusive = max(allDay.start, allDay.endExclusive.adding(days: -1))
            return .allDay(start: allDay.start, endInclusive: endInclusive)
        }
        return timed(start: event.start, end: event.end, zone: zone, day: day)
    }

    /// The local dates a timed span touches, `[start, end)`: an end at local midnight belongs to
    /// the previous day. A zero-length span touches only its start date.
    public static func daysTouched(start: Date, end: Date, zone: TimeZone) -> ClosedRange<CalendarDate> {
        let first = CalendarDate(start, in: zone)
        guard end > start else { return first...first }
        let lastInstant = end.addingTimeInterval(-0.001)
        let last = max(first, CalendarDate(lastInstant, in: zone))
        return first...last
    }

    static func days(of event: CalendarEvent, zone: TimeZone) -> ClosedRange<CalendarDate> {
        if let allDay = event.allDay {
            return allDay.start...max(allDay.start, allDay.endExclusive.adding(days: -1))
        }
        return daysTouched(start: event.start, end: event.end, zone: zone)
    }

    private static func timed(start: Date, end: Date, zone: TimeZone, day: CalendarDate) -> EventTiming {
        let span = daysTouched(start: start, end: end, zone: zone)
        return .timed(
            start: start,
            end: max(start, end),
            startsBeforeDay: span.lowerBound < day,
            endsAfterDay: span.upperBound > day
        )
    }
}
