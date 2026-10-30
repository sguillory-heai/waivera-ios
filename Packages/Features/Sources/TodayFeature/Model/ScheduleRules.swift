import Foundation
import WaiveraAPI
import WaiveraData

/// Schedule rules for Today: pending invitations, the next three items and today's
/// celebrations. Day boundaries and clock times use the employee's saved zone.
enum ScheduleRules {
    /// The days Today looks ahead for Next up and invitations: this week and the next.
    static let weeksAhead = 2

    /// The week anchors Today observes, in the employee's zone: the week containing today and
    /// the week after it, so Saturday still sees a week ahead.
    static func weekAnchors(today: CalendarDate) -> [CalendarDate] {
        (0..<weeksAhead).map { today.adding(days: 7 * $0) }
    }

    /// Events across the observed weeks, once each.
    static func events(in feeds: [CalendarFeed]) -> [CalendarEvent] {
        var seen = Set<String>()
        return feeds.flatMap(\.events).filter { seen.insert($0.id).inserted }
    }

    /// Invitations the API says are pending and not yet answered on this screen, soonest first.
    static func invitations(
        _ events: [CalendarEvent],
        now: Date,
        zone: TimeZone,
        answered: Set<String>
    ) -> [InvitationItem] {
        let today = CalendarDate(now, in: zone)
        return
            events
            .filter { $0.needsResponse(at: now) && !answered.contains($0.id) }
            .sorted { ($0.start, $0.id) < ($1.start, $1.id) }
            .map { event in
                InvitationItem(
                    eventId: event.id,
                    title: event.title?.trimmedNonEmpty,
                    organizer: event.ownerName?.trimmedNonEmpty,
                    time: label(for: event, now: now, zone: zone, today: today)
                )
            }
    }

    /// The next three items that have not ended. All-day items lead their day; pending and
    /// declined invitations are left out (pending ones are under Needs you).
    static func nextUp(_ events: [CalendarEvent], now: Date, zone: TimeZone) -> [NextUpItem] {
        let today = CalendarDate(now, in: zone)
        return
            events
            .filter { !hiddenResponses.contains($0.viewerResponse) && !hasEnded($0, now: now, today: today) }
            .sorted { lhs, rhs in
                let left = (firstDay(lhs, zone: zone, today: today), lhs.isAllDay ? 0 : 1, lhs.start)
                let right = (firstDay(rhs, zone: zone, today: today), rhs.isAllDay ? 0 : 1, rhs.start)
                if left != right { return left < right }
                return lhs.id < rhs.id
            }
            .prefix(NextUpSection.count)
            .map { item($0, now: now, zone: zone, today: today) }
    }

    static func celebrations(_ index: MilestoneIndex, on date: CalendarDate) -> [CelebrationItem] {
        index.celebrations(on: date).map { celebration in
            CelebrationItem(
                userId: celebration.userId,
                name: celebration.displayName?.trimmedNonEmpty,
                isBirthday: celebration.isBirthday,
                anniversaryYears: celebration.anniversaryYears
            )
        }
    }

    // MARK: Private

    private static let hiddenResponses: Set<InvitationState> = [.pending, .declined, .cancelled]

    private static func item(_ event: CalendarEvent, now: Date, zone: TimeZone, today: CalendarDate) -> NextUpItem {
        let timed = !event.isAllDay
        return NextUpItem(
            eventId: event.id,
            title: event.title?.trimmedNonEmpty,
            time: label(for: event, now: now, zone: zone, today: today),
            start: timed ? ClockTime(event.start, in: zone) : nil,
            end: timed && event.end > event.start ? ClockTime(event.end, in: zone) : nil,
            endsOnLaterDay: timed && endsOnLaterDay(event, zone: zone),
            location: event.location?.trimmedNonEmpty,
            isOnline: event.isOnline,
            startsToday: firstDay(event, zone: zone, today: today) == today
        )
    }

    private static func label(for event: CalendarEvent, now: Date, zone: TimeZone, today: CalendarDate)
        -> UpcomingLabel
    {
        if let span = event.allDay {
            return TimeLabels.allDay(start: span.start, endExclusive: span.endExclusive, today: today)
        }
        return TimeLabels.upcoming(
            start: event.start,
            end: event.end > event.start ? event.end : nil,
            now: now,
            zone: zone
        )
    }

    /// An overnight shift ends on a later day; an end at exactly midnight still belongs to the start day.
    private static func endsOnLaterDay(_ event: CalendarEvent, zone: TimeZone) -> Bool {
        guard event.end > event.start else { return false }
        let startDay = CalendarDate(event.start, in: zone)
        var lastDay = CalendarDate(event.end, in: zone)
        if ClockTime(event.end, in: zone) == .midnight { lastDay = lastDay.adding(days: -1) }
        return lastDay > startDay
    }

    /// All-day items end when their last day ends; timed items when their end instant passes.
    private static func hasEnded(_ event: CalendarEvent, now: Date, today: CalendarDate) -> Bool {
        if let span = event.allDay {
            let end = span.endExclusive > span.start ? span.endExclusive : span.start.adding(days: 1)
            return today >= end
        }
        return max(event.end, event.start) <= now
    }

    /// The first day the item shows on, from today on; all-day items that started earlier count as today.
    private static func firstDay(_ event: CalendarEvent, zone: TimeZone, today: CalendarDate) -> CalendarDate {
        let day = event.allDay?.start ?? CalendarDate(event.start, in: zone)
        return day < today ? today : day
    }
}
