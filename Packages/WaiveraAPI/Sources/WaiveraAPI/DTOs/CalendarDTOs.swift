import Foundation

/// Mirrors `CalendarFeedResponseDto` (`data` of `GET /api/CalendarEvent/GetAllEvent`).
public struct CalendarFeedResponseDto: Codable, Sendable, Equatable {
    public var events: [CalendarEventResponseDto]
    public var timeOff: [CalendarTimeOffResponseDto]
    public var holidays: [HolidayDto]

    enum CodingKeys: String, CodingKey { case events, timeOff, holidays }

    public init(events: [CalendarEventResponseDto], timeOff: [CalendarTimeOffResponseDto], holidays: [HolidayDto]) {
        self.events = events
        self.timeOff = timeOff
        self.holidays = holidays
    }

    /// Malformed rows are dropped, like the Expo normalisers (07 §2).
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        events = container.lenientArray(CalendarEventResponseDto.self, forKey: .events)
        timeOff = container.lenientArray(CalendarTimeOffResponseDto.self, forKey: .timeOff)
        holidays = container.lenientArray(HolidayDto.self, forKey: .holidays)
    }
}

/// `inviteStatus` on an attendee. Declared `string` in C#, so a string on both transports.
public enum AttendeeInviteStatus: String, OpenEnum {
    case invited = "INVITED"
    case accepted = "ACCEPTED"
    case declined = "DECLINED"
    case tentative = "TENTATIVE"
    case cancelled = "CANCELLED"
    case unknown = "UNKNOWN"
    public static var unknownCase: AttendeeInviteStatus { .unknown }
}

public enum AttendeeType: String, OpenEnum {
    case employee = "EMPLOYEE"
    case waiverParticipant = "WAIVER_PARTICIPANT"
    case external = "EXTERNAL"
    case unknown = "UNKNOWN"
    public static var unknownCase: AttendeeType { .unknown }
}

/// Mirrors `AttendeeResponseDto`.
public struct AttendeeResponseDto: Codable, Sendable, Hashable {
    public var attendeeId: String
    public var type: AttendeeType?
    public var ref: String?
    public var email: String?
    public var displayName: String?
    public var inviteStatus: AttendeeInviteStatus?
    public var respondedAt: Date?
}

/// Mirrors `CalendarEventResponseDto`. `startTime`/`endTime` are zone-less UTC instants.
public struct CalendarEventResponseDto: Codable, Sendable, Hashable {
    public var id: String
    public var title: String?
    public var startTime: Date
    public var endTime: Date
    public var description: String?
    public var ownerUserID: String?
    public var ownerName: String?
    public var meetingDetails: String?
    public var location: String?
    public var createdby: String?
    public var attendees: [AttendeeResponseDto]?
    public var ownerColor: String?
    public var taskId: Int?
    public var taskTitle: String?
    public var online: Bool?
    public var isSprout: Bool?
    public var recurrenceRule: String?
    /// The event's own recurrence zone; never rewritten by the client.
    public var timeZoneId: String?
    public var allDayStart: CalendarDate?
    public var allDayEndExclusive: CalendarDate?
    public var allDayExceptionDate: CalendarDate?
    public var cancelledAllDayDates: [CalendarDate]?
    public var parentEventId: String?
    public var exceptionDate: Date?
    public var isInvitationAccept: Bool?
    public var meetingType: String?
    public var crossesMidnight: Bool?
    public var displayDate: Date?
    /// Server-rendered; display as-is or ignore, never re-localise.
    public var formattedDateRange: String?
}

/// Mirrors `CalendarTimeOffResponseDto` (these two instants do carry `Z`).
public struct CalendarTimeOffResponseDto: Codable, Sendable, Hashable {
    public var id: Int
    public var userId: String?
    public var startTime: Date
    public var endTime: Date
    public var leaveType: String?
    public var requestType: String?
    public var durationMinutes: Int?
    public var comment: String?
    public var status: String?
    public var isCancellationPending: Bool?
    public var canDelete: Bool?
}

/// Mirrors `HolidayDto`. The `DateTime` bounds are calendar dates in meaning, so only the
/// date part is kept (client decision; avoids drifting a holiday a day west of UTC).
public struct HolidayDto: Codable, Sendable, Hashable {
    public var id: Int
    public var title: String?
    public var description: String?
    public var startDate: CalendarDate
    public var endDate: CalendarDate
}

/// Mirrors `CalendarEmployeeMilestoneResponseDto` (`GET /api/CalendarEvent/milestones`).
public struct CalendarEmployeeMilestoneResponseDto: Codable, Sendable, Hashable {
    public enum MilestoneType: String, OpenEnum {
        case birthday = "BIRTHDAY"
        case workAnniversary = "WORK_ANNIVERSARY"
        case unknown = "UNKNOWN"
        public static var unknownCase: MilestoneType { .unknown }
    }

    public var type: MilestoneType
    public var userId: String
    public var displayName: String?
    public var avatarUrl: String?
    public var roles: [String]?
    /// 1-based.
    public var month: Int
    public var day: Int
    /// Hire year, work anniversaries only. Birth years are never returned.
    public var startYear: Int?
}

/// Mirrors `InternalInvitationResponseReq` (`POST /api/invitation/AcceptDenyMeeting`).
public struct InternalInvitationResponseReq: Codable, Sendable, Equatable {
    public var calendarEventId: String
    public var isInvitationAccept: Bool
    /// Ignored by the server (the actor comes from the token); sent for parity.
    public var userId: String?

    public init(calendarEventId: String, isInvitationAccept: Bool, userId: String?) {
        self.calendarEventId = calendarEventId
        self.isInvitationAccept = isInvitationAccept
        self.userId = userId
    }
}
