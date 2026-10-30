import Foundation
import WaiveraAPI
import WaiveraData

/// Today's timed events on a track from `windowStart` to `windowEnd` (8 AM to 6 PM, widened to
/// fit the day's events). Positions are shares of the window's real duration, so on a DST day
/// every event and hour sits where its instant falls.
struct DayTimeline: Hashable, Sendable {
    var windowStart: ClockTime
    var windowEnd: ClockTime
    var blocks: [DayBlock]
    /// Every whole hour inside the window.
    var ticks: [Double]
    /// Every other hour from the window's start, with its clock time.
    var labels: [DayHourLabel]
    /// Where now falls, while it is inside the window.
    var now: Double?
    var eventCount: Int
    /// Time covered by events, overlaps counted once.
    var scheduled: TimeInterval
}

/// One event on the track; `tone` cycles through the track's three colours in start order.
struct DayBlock: Hashable, Sendable {
    var eventId: String
    var start: Double
    var end: Double
    var tone: Int
}

struct DayHourLabel: Hashable, Sendable {
    var at: Double
    var time: ClockTime
}

/// The hero's stats and the "Your day" track. Day and week boundaries are local midnights in the
/// employee's saved zone, turned into instants with the zone's own rules, so a 23- or 25-hour day
/// is measured as it really runs (`sprout_api/docs/timezone-standard.md`).
enum DayRules {
    static let defaultStartHour = 8
    static let defaultEndHour = 18
    static let labelEveryHours = 2
    static let tones = 3
    private static let hoursPerDay = 24

    /// Events the person is going to: not an unanswered invitation, not one they declined.
    static func attending(_ events: [CalendarEvent]) -> [CalendarEvent] {
        events.filter { !skipped.contains($0.viewerResponse) }
    }

    static func stats(
        conversations: SourceStatus,
        conversationList: [Conversation],
        schedule: SourceStatus,
        events: [CalendarEvent],
        zone: TimeZone,
        today: CalendarDate
    ) -> TodayStats {
        let going = attending(events)
        let weekStart = today.startOfWeek
        return TodayStats(
            eventsToday: schedule.isReady
                ? going.filter { overlaps($0, from: today, until: today.adding(days: 1), zone: zone) }.count : nil,
            unreadChats: conversations.isReady
                ? conversationList.filter { $0.unreadCount > 0 && !$0.isArchived }.count : nil,
            eventsThisWeek: schedule.isReady
                ? going.filter { overlaps($0, from: weekStart, until: weekStart.adding(days: 7), zone: zone) }.count
                : nil
        )
    }

    /// Whether `event` covers any of `[from, until)`, local days in `zone`.
    static func overlaps(_ event: CalendarEvent, from: CalendarDate, until: CalendarDate, zone: TimeZone) -> Bool {
        if let span = event.allDay {
            let end = span.endExclusive > span.start ? span.endExclusive : span.start.adding(days: 1)
            return span.start < until && end > from
        }
        let rangeStart = from.startInstant(in: zone)
        let rangeEnd = until.startInstant(in: zone)
        guard event.end > event.start else { return event.start >= rangeStart && event.start < rangeEnd }
        return event.start < rangeEnd && event.end > rangeStart
    }

    /// Today's track, or `nil` until the schedule has loaded. All-day items stay off the track.
    static func timeline(
        events: [CalendarEvent],
        schedule: SourceStatus,
        zone: TimeZone,
        today: CalendarDate,
        now: Date
    ) -> DayTimeline? {
        guard schedule.isReady else { return nil }
        let dayStart = today.startInstant(in: zone)
        let dayEnd = today.adding(days: 1).startInstant(in: zone)
        let spans = attending(events)
            .filter { !$0.isAllDay && overlaps($0, from: today, until: today.adding(days: 1), zone: zone) }
            .map { event in
                let end = event.end > event.start ? event.end : event.start
                return Span(id: event.id, start: max(event.start, dayStart), end: min(end, dayEnd))
            }
            .sorted { ($0.start, $0.end, $0.id) < ($1.start, $1.end, $1.id) }
        let clock = LocalClock(today: today, zone: zone, dayStart: dayStart, dayEnd: dayEnd)
        let startHour = min(defaultStartHour, spans.map { clock.floorHour($0.start) }.min() ?? hoursPerDay)
        let endHour = max(defaultEndHour, spans.map { clock.ceilHour($0.end) }.max() ?? 0)
        let window = Window(start: clock.instant(hour: startHour), end: clock.instant(hour: endHour))
        let ticks = startHour + 1 < endHour ? (startHour + 1..<endHour).map { window.at(clock.instant(hour: $0)) } : []
        let labels = stride(from: startHour, through: endHour, by: labelEveryHours).map {
            DayHourLabel(at: window.at(clock.instant(hour: $0)), time: ClockTime(hour: $0 % hoursPerDay, minute: 0))
        }
        return DayTimeline(
            windowStart: ClockTime(hour: startHour % hoursPerDay, minute: 0),
            windowEnd: ClockTime(hour: endHour % hoursPerDay, minute: 0),
            blocks: spans.enumerated().map { index, span in
                DayBlock(eventId: span.id, start: window.at(span.start), end: window.at(span.end), tone: index % tones)
            },
            ticks: ticks,
            labels: labels,
            now: now >= window.start && now <= window.end ? window.at(now) : nil,
            eventCount: spans.count,
            scheduled: covered(spans)
        )
    }

    /// The union of the spans' durations: two overlapping visits count their shared hour once.
    private static func covered(_ spans: [Span]) -> TimeInterval {
        var total: TimeInterval = 0
        var run: (start: Date, end: Date)?
        for span in spans {
            if let current = run, span.start <= current.end {
                run = (current.start, max(current.end, span.end))
            } else {
                if let current = run { total += current.end.timeIntervalSince(current.start) }
                run = (span.start, span.end)
            }
        }
        if let current = run { total += current.end.timeIntervalSince(current.start) }
        return total
    }

    private static let skipped: Set<InvitationState> = [.pending, .declined, .cancelled]

    private struct Span {
        var id: String
        var start: Date
        var end: Date
    }

    /// Whole local hours of `today` as instants, in the employee's zone.
    private struct LocalClock {
        let today: CalendarDate
        let zone: TimeZone
        let dayStart: Date
        let dayEnd: Date

        private var calendar: Calendar {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = zone
            return calendar
        }

        /// The instant of a whole local hour today; hour 24 is the next local midnight.
        func instant(hour: Int) -> Date {
            guard hour > 0 else { return dayStart }
            guard hour < DayRules.hoursPerDay else { return dayEnd }
            let parts = DateComponents(year: today.year, month: today.month, day: today.day, hour: hour)
            return calendar.date(from: parts) ?? dayStart.addingTimeInterval(TimeInterval(hour) * 3_600)
        }

        func floorHour(_ at: Date) -> Int {
            at <= dayStart ? 0 : calendar.component(.hour, from: at)
        }

        func ceilHour(_ at: Date) -> Int {
            guard at < dayEnd else { return DayRules.hoursPerDay }
            let parts = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: at)
            let hour = parts.hour ?? 0
            let onTheHour = parts.minute == 0 && parts.second == 0 && (parts.nanosecond ?? 0) < 1_000_000
            return onTheHour ? hour : hour + 1
        }
    }

    private struct Window {
        let start: Date
        let end: Date

        /// The share of the window at `instant`, clamped to it.
        func at(_ instant: Date) -> Double {
            let length = max(1, end.timeIntervalSince(start))
            return min(1, max(0, instant.timeIntervalSince(start) / length))
        }
    }
}

/// Where each hour label under the track starts, or `nil` when it is dropped: centred on its
/// share of `total`, kept inside, and skipped when it would come within `gap` of the last label
/// kept. Labels that would collide at large text are dropped, never overlapped.
enum AxisLabelPlacement {
    static func place(centers: [Double], widths: [Double], total: Double, gap: Double) -> [Double?] {
        var lastEnd: Double?
        return zip(centers, widths).map { center, width in
            let ideal = total * min(1, max(0, center)) - width / 2
            let x = min(max(0, ideal), max(0, total - width))
            if let end = lastEnd, x < end + gap { return nil }
            lastEnd = x + width
            return x
        }
    }
}
