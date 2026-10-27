import Foundation
import WaiveraAPI

/// Calendar, milestone and profile DTOs to domain models. Instants stay instants; date-only
/// values stay `CalendarDate` and are never pushed through a zone (dates.md).
public struct CalendarMapper: Sendable {
    public var viewerId: String

    public init(viewerId: String) {
        self.viewerId = viewerId
    }

    public func feed(_ dto: CalendarFeedResponseDto) -> CalendarFeed {
        CalendarFeed(
            events: dto.events.map(event),
            timeOff: dto.timeOff.map(Self.timeOff),
            holidays: dto.holidays.map(Self.holiday)
        )
    }

    public func event(_ dto: CalendarEventResponseDto) -> CalendarEvent {
        var event = CalendarEvent(id: dto.id, title: dto.title?.nilIfBlank, start: dto.startTime, end: dto.endTime)
        if let start = dto.allDayStart {
            let end = dto.allDayEndExclusive.flatMap { $0 > start ? $0 : nil } ?? start.adding(days: 1)
            event.allDay = .init(start: start, endExclusive: end, cancelledDates: dto.cancelledAllDayDates ?? [])
        }
        event.details = dto.description?.nilIfBlank
        event.location = dto.location?.nilIfBlank
        event.meetingDetails = dto.meetingDetails?.nilIfBlank
        event.ownerId = dto.ownerUserID ?? dto.createdby
        event.ownerName = dto.ownerName?.nilIfBlank
        event.ownerColor = dto.ownerColor?.nilIfBlank
        event.attendees = (dto.attendees ?? []).map(Self.attendee)
        event.isSprout = dto.isSprout ?? false
        event.isOnline = dto.online ?? false
        event.recurrenceRule = dto.recurrenceRule?.nilIfBlank
        event.parentEventId = dto.parentEventId?.nilIfBlank
        event.meetingType = dto.meetingType?.nilIfBlank
        event.taskId = dto.taskId
        event.taskTitle = dto.taskTitle?.nilIfBlank
        event.isOwner = event.ownerId == viewerId
        event.viewerResponse = viewerResponse(dto, attendees: event.attendees)
        return event
    }

    /// The attendee row for the viewer wins; `isInvitationAccept` is only a fallback, and a
    /// null there means "not invited / unknown", never pending (PLAN parity fix).
    func viewerResponse(_ dto: CalendarEventResponseDto, attendees: [CalendarAttendee]) -> InvitationState {
        if let mine = attendees.first(where: { $0.ref == viewerId }) { return mine.response }
        switch dto.isInvitationAccept {
        case true?: return .accepted
        case false?: return .declined
        case nil: return .notInvited
        }
    }

    static func attendee(_ dto: AttendeeResponseDto) -> CalendarAttendee {
        let kind: CalendarAttendee.Kind =
            switch dto.type {
            case .employee, nil: .employee
            case .waiverParticipant: .waiverParticipant
            case .external: .external
            case .unknown: .unknown
            }
        return CalendarAttendee(
            id: dto.attendeeId,
            kind: kind,
            ref: dto.ref?.nilIfBlank,
            displayName: dto.displayName?.nilIfBlank,
            email: dto.email?.nilIfBlank,
            response: response(dto.inviteStatus)
        )
    }

    static func response(_ status: AttendeeInviteStatus?) -> InvitationState {
        switch status {
        case nil: .notInvited
        case .invited: .pending
        case .accepted: .accepted
        case .declined: .declined
        case .tentative: .tentative
        case .cancelled: .cancelled
        case .unknown: .unknown
        }
    }

    static func timeOff(_ dto: CalendarTimeOffResponseDto) -> CalendarTimeOff {
        var entry = CalendarTimeOff(
            id: dto.id,
            start: dto.startTime,
            end: dto.endTime,
            leaveType: dto.leaveType?.nilIfBlank
        )
        entry.userId = dto.userId
        entry.requestType = dto.requestType?.nilIfBlank
        entry.status = dto.status?.nilIfBlank
        entry.durationMinutes = dto.durationMinutes
        return entry
    }

    static func holiday(_ dto: HolidayDto) -> Holiday {
        Holiday(
            id: dto.id,
            title: dto.title?.nilIfBlank,
            details: dto.description?.nilIfBlank,
            start: dto.startDate,
            end: max(dto.startDate, dto.endDate)
        )
    }

    public static func milestone(_ dto: CalendarEmployeeMilestoneResponseDto) -> Milestone? {
        let kind: Milestone.Kind
        switch dto.type {
        case .birthday: kind = .birthday
        case .workAnniversary: kind = .workAnniversary
        case .unknown: return nil
        }
        guard (1...12).contains(dto.month), (1...31).contains(dto.day) else { return nil }
        return Milestone(
            kind: kind,
            userId: dto.userId,
            displayName: dto.displayName?.nilIfBlank,
            month: dto.month,
            day: dto.day,
            startYear: dto.startYear,
            avatarURL: dto.avatarUrl?.nilIfBlank
        )
    }
}
