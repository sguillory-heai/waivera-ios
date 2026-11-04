import Foundation
import WaiveraAPI

/// `CalendarEventDto` for CreateEvent and UpdateEventbyId, built the way the web's Add event form
/// builds it: wall times in the saved zone become UTC instants (so 9 AM stays 9 AM across a DST
/// change), an all-day event spans zoned midnights plus its literal dates, a Waivera video
/// meeting is `isSprout: false` with location "Waivera", and `online` is always true.
public enum EventPayload {
    public static let waiveraLocation = "Waivera"

    public static func build(
        _ draft: EventDraft,
        zone: TimeZone,
        ownerId: String,
        existing: CalendarEvent? = nil
    ) -> CalendarEventDto {
        let next = draft.date.adding(days: 1)
        let start: Date
        let end: Date
        if draft.allDay {
            start = draft.date.startInstant(in: zone)
            end = next.startInstant(in: zone)
        } else {
            start = draft.date.instant(atMinute: draft.startMinute, in: zone)
            end = draft.date.instant(atMinute: draft.endMinute, in: zone)
        }
        let isAllDay: Bool? = draft.allDay ? true : (existing?.isAllDay == true ? false : nil)
        return CalendarEventDto(
            title: draft.title.trimmed,
            description: draft.description?.trimmed ?? "",
            location: draft.waiveraVideo ? waiveraLocation : (draft.location?.trimmed ?? ""),
            meetingDetails: existing?.meetingDetails ?? "",
            ownerUserID: ownerId,
            startTime: start,
            endTime: end,
            isAllDay: isAllDay,
            allDayStart: draft.allDay ? draft.date.isoString : nil,
            allDayEndExclusive: draft.allDay ? next.isoString : nil,
            timeZone: zone.identifier,
            online: true,
            isSprout: !draft.waiveraVideo,
            notifyParticipants: draft.notifyParticipants && !draft.participantIds.isEmpty,
            attendees: attendees(draft, ownerId: ownerId, existing: existing)
        )
    }

    private static func attendees(_ draft: EventDraft, ownerId: String, existing: CalendarEvent?)
        -> [AttendeeRequestDto]
    {
        let coworkers = unique(draft.inviteeIds.filter { $0 != ownerId })
            .map { AttendeeRequestDto(type: .employee, ref: $0) }
        let participants = unique(draft.participantIds).map { AttendeeRequestDto(type: .waiverParticipant, ref: $0) }
        // An edit keeps the guests the phone does not manage: outside emails.
        let outside = unique((existing?.attendees ?? []).filter { $0.kind == .external }.compactMap(\.email))
            .map { AttendeeRequestDto(type: .external, email: $0) }
        return coworkers + participants + outside
    }

    /// Participants already invited to `event`, for the edit form.
    public static func participants(_ event: CalendarEvent) -> [String] {
        unique(event.attendees.filter { $0.kind == .waiverParticipant }.compactMap { $0.ref?.nilIfBlank })
    }

    /// Coworkers already invited to `event`, for the edit form.
    public static func invitees(_ event: CalendarEvent) -> [String] {
        unique(event.attendees.filter { $0.kind == .employee && $0.ref != event.ownerId }.compactMap(\.ref))
    }

    private static func unique(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.filter { seen.insert($0).inserted }
    }
}
