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

/// Mirrors `dto/Request/CalendarEventDto.cs` `AttendeeRequestDto`.
public struct AttendeeRequestDto: Encodable, Sendable, Hashable {
    public var type: String
    public var ref: String?
    public var email: String?

    public init(type: AttendeeType, ref: String? = nil, email: String? = nil) {
        self.type = type.rawValue
        self.ref = ref
        self.email = email
    }
}

/// Mirrors `dto/Request/CalendarEventDto.cs` for `CreateEvent` and `UpdateEventbyId`. Times are
/// UTC instants; the all-day fields are literal dates. Unset optionals are left out, as the web does.
public struct CalendarEventDto: Encodable, Sendable, Hashable {
    public var title: String
    public var description: String
    public var location: String
    public var meetingDetails: String
    public var ownerUserID: String
    public var startTime: Date
    public var endTime: Date
    public var isAllDay: Bool?
    public var allDayStart: String?
    public var allDayEndExclusive: String?
    public var timeZone: String
    public var online: Bool
    public var isSprout: Bool
    public var notifyParticipants: Bool
    public var attendees: [AttendeeRequestDto]

    enum CodingKeys: String, CodingKey {
        case title, description, location, meetingDetails, ownerUserID, startTime, endTime, isAllDay
        case allDayStart, allDayEndExclusive, online, isSprout, notifyParticipants, attendees
        case timeZone = "time_zone"
    }

    public init(
        title: String,
        description: String,
        location: String,
        meetingDetails: String,
        ownerUserID: String,
        startTime: Date,
        endTime: Date,
        isAllDay: Bool?,
        allDayStart: String?,
        allDayEndExclusive: String?,
        timeZone: String,
        online: Bool,
        isSprout: Bool,
        notifyParticipants: Bool,
        attendees: [AttendeeRequestDto]
    ) {
        self.title = title
        self.description = description
        self.location = location
        self.meetingDetails = meetingDetails
        self.ownerUserID = ownerUserID
        self.startTime = startTime
        self.endTime = endTime
        self.isAllDay = isAllDay
        self.allDayStart = allDayStart
        self.allDayEndExclusive = allDayEndExclusive
        self.timeZone = timeZone
        self.online = online
        self.isSprout = isSprout
        self.notifyParticipants = notifyParticipants
        self.attendees = attendees
    }
}

/// Mirrors `dto/Response/Calendar/CalendarDirectoryOptionsDto.cs` (`GET attendee-options`).
public struct CalendarDirectoryOptionsDto: Decodable, Sendable, Hashable {
    public var people: [CalendarDirectoryPersonDto]

    public init(people: [CalendarDirectoryPersonDto]) { self.people = people }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        people =
            try container.decodeIfPresent(LossyArray<CalendarDirectoryPersonDto>.self, forKey: .people)?.elements ?? []
    }

    enum CodingKeys: String, CodingKey { case people }
}

public struct CalendarDirectoryPersonDto: Decodable, Sendable, Hashable {
    public var id: String
    public var name: String
    public var email: String?
    /// "Employee" or "Participant" (the directory's own names).
    public var type: String

    public init(id: String, name: String, email: String? = nil, type: String) {
        self.id = id
        self.name = name
        self.email = email
        self.type = type
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(LenientID.self, forKey: .id)?.value ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? ""
        email = try container.decodeIfPresent(String.self, forKey: .email)
        type = try container.decodeIfPresent(String.self, forKey: .type) ?? ""
    }

    enum CodingKeys: String, CodingKey { case id, name, email, type }
}
