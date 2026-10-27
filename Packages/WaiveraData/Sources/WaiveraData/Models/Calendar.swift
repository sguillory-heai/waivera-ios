import Foundation
import WaiveraAPI

/// The signed-in employee's answer to an invitation. `notInvited` when the API says nothing:
/// a null acceptance is never read as pending (PLAN parity fix, 07 §7).
public enum InvitationState: String, Codable, Sendable, Hashable {
    case notInvited, pending, accepted, declined, tentative, cancelled, unknown
}

public struct CalendarAttendee: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable, Hashable {
        case employee, waiverParticipant, external, unknown
    }

    public var id: String
    public var kind: Kind
    /// The backend user id for employees.
    public var ref: String?
    public var displayName: String?
    public var email: String?
    public var response: InvitationState

    public init(
        id: String,
        kind: Kind,
        ref: String?,
        displayName: String?,
        email: String? = nil,
        response: InvitationState
    ) {
        self.id = id
        self.kind = kind
        self.ref = ref
        self.displayName = displayName
        self.email = email
        self.response = response
    }
}

public struct CalendarEvent: Codable, Sendable, Hashable, Identifiable {
    /// A whole-day span, `[start, endExclusive)` as dates with no zone.
    public struct AllDaySpan: Codable, Sendable, Hashable {
        public var start: CalendarDate
        public var endExclusive: CalendarDate
        public var cancelledDates: [CalendarDate]

        public init(start: CalendarDate, endExclusive: CalendarDate, cancelledDates: [CalendarDate] = []) {
            self.start = start
            self.endExclusive = endExclusive
            self.cancelledDates = cancelledDates
        }

        public func contains(_ date: CalendarDate) -> Bool {
            date >= start && date < endExclusive && !cancelledDates.contains(date)
        }
    }

    public static let joinLeadTime: TimeInterval = 30 * 60

    public var id: String
    public var title: String?
    public var start: Date
    public var end: Date
    public var allDay: AllDaySpan?
    public var details: String?
    public var location: String?
    public var meetingDetails: String?
    public var ownerId: String?
    public var ownerName: String?
    /// The owner's colour as the API sends it; the design system validates it.
    public var ownerColor: String?
    public var attendees: [CalendarAttendee]
    public var isSprout: Bool
    public var isOnline: Bool
    public var recurrenceRule: String?
    public var parentEventId: String?
    public var meetingType: String?
    public var taskId: Int?
    public var taskTitle: String?
    public var isOwner: Bool
    public var viewerResponse: InvitationState

    public init(id: String, title: String?, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        attendees = []
        isSprout = false
        isOnline = false
        isOwner = false
        viewerResponse = .notInvited
    }

    public var isAllDay: Bool { allDay != nil }

    /// The first `http(s)` link in the meeting details or location.
    public var joinURL: URL? {
        for candidate in [meetingDetails, location] {
            guard let raw = candidate?.trimmed, let url = URL(string: raw),
                let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", url.host != nil
            else { continue }
            return url
        }
        return nil
    }

    public var canJoin: Bool { isSprout || joinURL != nil }

    /// From 30 minutes before the start to the end; zone independent.
    public func isJoinWindowOpen(at now: Date) -> Bool {
        now >= start.addingTimeInterval(-Self.joinLeadTime) && now <= end
    }

    /// Accept/Decline is offered only when the API says the invitation is pending.
    public func needsResponse(at now: Date) -> Bool {
        !isOwner && viewerResponse == .pending && now < start
    }

    /// Whether the event shows on `date` in the employee's zone. Timed events use half-open
    /// intervals, so an event ending at midnight does not spill into the next day.
    public func occurs(on date: CalendarDate, in timeZone: TimeZone) -> Bool {
        if let allDay { return allDay.contains(date) }
        let day = date.interval(in: timeZone)
        if start == end { return day.start <= start && start < day.end }
        return start < day.end && end > day.start
    }
}

public struct CalendarTimeOff: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var userId: String?
    public var start: Date
    public var end: Date
    public var leaveType: String?
    public var requestType: String?
    public var status: String?
    public var durationMinutes: Int?

    public init(id: Int, start: Date, end: Date, leaveType: String? = nil) {
        self.id = id
        self.start = start
        self.end = end
        self.leaveType = leaveType
    }

    public func occurs(on date: CalendarDate, in timeZone: TimeZone) -> Bool {
        let day = date.interval(in: timeZone)
        return start < day.end && end > day.start
    }
}

public struct Holiday: Codable, Sendable, Hashable, Identifiable {
    public var id: Int
    public var title: String?
    public var details: String?
    public var start: CalendarDate
    /// Inclusive.
    public var end: CalendarDate

    public init(id: Int, title: String?, details: String? = nil, start: CalendarDate, end: CalendarDate) {
        self.id = id
        self.title = title
        self.details = details
        self.start = start
        self.end = end
    }

    public func occurs(on date: CalendarDate) -> Bool { date >= start && date <= end }
}

public struct CalendarFeed: Codable, Sendable, Hashable {
    public var events: [CalendarEvent]
    public var timeOff: [CalendarTimeOff]
    public var holidays: [Holiday]

    public init(events: [CalendarEvent] = [], timeOff: [CalendarTimeOff] = [], holidays: [Holiday] = []) {
        self.events = events.sorted { ($0.start, $0.id) < ($1.start, $1.id) }
        self.timeOff = timeOff
        self.holidays = holidays
    }

    public var isEmpty: Bool { events.isEmpty && timeOff.isEmpty && holidays.isEmpty }

    /// One day's agenda in the fixed order (07 §3), events sorted by instant.
    public func agenda(on date: CalendarDate, in timeZone: TimeZone, celebrations: [Celebration]) -> DayAgenda {
        DayAgenda(
            date: date,
            celebrations: celebrations,
            holidays: holidays.filter { $0.occurs(on: date) },
            timeOff: timeOff.filter { $0.occurs(on: date, in: timeZone) },
            events: events.filter { $0.occurs(on: date, in: timeZone) }
        )
    }

    /// Dates in `days` that have anything scheduled, for grid dots.
    public func busyDates(_ days: [CalendarDate], in timeZone: TimeZone) -> Set<CalendarDate> {
        Set(days.filter { !agenda(on: $0, in: timeZone, celebrations: []).isEmpty })
    }
}

public struct DayAgenda: Sendable, Hashable {
    public var date: CalendarDate
    public var celebrations: [Celebration]
    public var holidays: [Holiday]
    public var timeOff: [CalendarTimeOff]
    public var events: [CalendarEvent]

    public var isEmpty: Bool { celebrations.isEmpty && holidays.isEmpty && timeOff.isEmpty && events.isEmpty }
}

/// The calendar views and the range each one renders and fetches (07 §2: the full grid).
public enum CalendarPeriod: String, Codable, Sendable, Hashable, CaseIterable {
    case day, week, month

    /// Every date the view shows for `date`: 1, 7 or 42.
    public func dates(containing date: CalendarDate) -> [CalendarDate] {
        let first: CalendarDate
        let count: Int
        switch self {
        case .day: (first, count) = (date, 1)
        case .week: (first, count) = (date.startOfWeek, 7)
        case .month: (first, count) = (date.firstOfMonth.startOfWeek, 42)
        }
        return (0..<count).map { first.adding(days: $0) }
    }

    /// The instants to fetch: from the first shown date's start to the end of the last.
    public func fetchInterval(containing date: CalendarDate, in timeZone: TimeZone) -> DateInterval {
        let dates = dates(containing: date)
        let first = dates.first ?? date
        let last = dates.last ?? date
        return DateInterval(
            start: first.startInstant(in: timeZone),
            end: last.adding(days: 1).startInstant(in: timeZone)
        )
    }

    /// The anchor date for the previous or next page of this view.
    public func step(_ date: CalendarDate, by amount: Int) -> CalendarDate {
        switch self {
        case .day: date.adding(days: amount)
        case .week: date.adding(days: 7 * amount)
        case .month: date.firstOfMonth.addingMonths(amount)
        }
    }
}

/// The answer to a single-event lookup (`CalendarRepository.event(id:)`).
public enum EventLookup: Sendable, Hashable {
    case found(CalendarEvent)
    /// The server has no such event for this person: deleted, or another organization.
    case notFound

    public var event: CalendarEvent? {
        if case .found(let event) = self { return event }
        return nil
    }
}

extension CalendarEvent {
    /// Recurring occurrences carry a composite id, `<36-character series id>-<occurrence
    /// instant>` (sprout_api `CalendarEventController.UpdateEvent`). `GetEventbyId` only knows
    /// the series id, so an occurrence is found through the feed of its own date instead.
    public static func occurrenceInstant(fromId id: String) -> Date? {
        guard id.count > 37 else { return nil }
        let separator = id.index(id.startIndex, offsetBy: 36)
        guard id[separator] == "-" else { return nil }
        return WaiveraInstant.parse(String(id[id.index(after: separator)...]))
    }
}
