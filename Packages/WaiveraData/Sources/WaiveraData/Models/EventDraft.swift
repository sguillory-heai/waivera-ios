import Foundation
import WaiveraAPI

/// A quick event as the form holds it: one day, wall-clock minutes in the employee's saved zone.
/// It becomes UTC instants only when sent. Recurrence and linked tasks stay on the web.
public struct EventDraft: Sendable, Hashable {
    public var title: String
    public var date: CalendarDate
    /// Minutes since midnight; ignored for all-day events.
    public var startMinute: Int
    public var endMinute: Int
    public var allDay: Bool
    public var inviteeIds: [String]
    public var participantIds: [String]
    /// Email the invited participants (only sent when there are any).
    public var notifyParticipants: Bool
    public var waiveraVideo: Bool
    public var location: String?
    public var description: String?

    public init(
        title: String,
        date: CalendarDate,
        startMinute: Int,
        endMinute: Int,
        allDay: Bool = false,
        inviteeIds: [String] = [],
        participantIds: [String] = [],
        notifyParticipants: Bool = false,
        waiveraVideo: Bool = true,
        location: String? = nil,
        description: String? = nil
    ) {
        self.title = title
        self.date = date
        self.startMinute = startMinute
        self.endMinute = endMinute
        self.allDay = allDay
        self.inviteeIds = inviteeIds
        self.participantIds = participantIds
        self.notifyParticipants = notifyParticipants
        self.waiveraVideo = waiveraVideo
        self.location = location
        self.description = description
    }
}

/// Someone the employee can invite: a coworker or a waiver participant.
public struct AttendeeOption: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var email: String?
    public var isParticipant: Bool

    public init(id: String, name: String, email: String? = nil, isParticipant: Bool = false) {
        self.id = id
        self.name = name
        self.email = email
        self.isParticipant = isParticipant
    }

    /// Coworker and participant ids come from different tables, so the kind is part of the key.
    public var key: String { isParticipant ? "participant:\(id)" : "employee:\(id)" }
}
