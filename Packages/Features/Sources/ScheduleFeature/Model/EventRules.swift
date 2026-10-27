import Foundation
import WaiveraAPI
import WaiveraData

/// Where a local Accept/Decline stands.
public enum ResponsePhase: Sendable, Hashable {
    /// Nothing local; the server's answer shows.
    case idle
    /// Chosen locally; Undo is still possible and nothing has been sent.
    case undoWindow
    /// Sent; waiting for the server.
    case saving
    /// The server accepted it.
    case saved
}

/// A local answer layered over the server's event.
public struct OptimisticResponse: Sendable, Hashable {
    public var accept: Bool
    public var phase: ResponsePhase
}

/// A failed save, kept so the screen offers Retry for the same choice.
public struct ResponseFailure: Sendable, Hashable {
    public var accept: Bool
    public var error: WaiveraError
}

/// The invitation block. `response` is what to show now (including an optimistic answer);
/// Accept/Decline show only while `canChange`.
public struct InvitationUI: Sendable, Hashable {
    public var response: InvitationState
    public var canChange: Bool
    public var phase: ResponsePhase
    public var failure: ResponseFailure?
}

public enum JoinState: Sendable, Hashable {
    case open, tooEarly, ended, noTime
}

public enum JoinError: Sendable, Hashable {
    /// Neither the meeting details nor the location hold an http(s) link (07 §7).
    case noLink
    /// The lobby could not be created or opened.
    case failed(WaiveraError?)
}

public struct JoinUI: Sendable, Hashable {
    public var state: JoinState
    /// When Join opens: 30 minutes before the start.
    public var opensAt: Date?
    public var isBusy: Bool
    public var error: JoinError?
}

public struct AttendeeRow: Sendable, Hashable, Identifiable {
    public var id: String
    /// Backend user id for employees; nil for participants and guests.
    public var userId: String?
    public var name: String?
    public var email: String?
    public var response: InvitationState
    /// Only computed for employees (07 §7: other attendees get no badge).
    public var celebration: ScheduleCelebration?
    public var isMe: Bool
    public var isEmployee: Bool
}

/// Pure rules for the event screen (07 §7), kept apart from the model so each acceptance check
/// has a direct test.
public enum EventRules {
    /// Answers an invited attendee can hold. `notInvited` (a null `isInvitationAccept`),
    /// `cancelled` and `unknown` never get buttons (PLAN parity fix).
    static let answerable: Set<InvitationState> = [.pending, .accepted, .declined, .tentative]

    public static func isOrganizer(_ event: CalendarEvent, myUserId: String?) -> Bool {
        event.isOwner || (myUserId != nil && event.ownerId == myUserId)
    }

    /// True until the event starts: its start instant, or local midnight of an all-day start.
    public static func notStarted(_ event: CalendarEvent, now: Date, zone: TimeZone) -> Bool {
        if let allDay = event.allDay { return now < allDay.start.startInstant(in: zone) }
        return now < event.start
    }

    public static func invitation(
        _ event: CalendarEvent,
        myUserId: String?,
        now: Date,
        zone: TimeZone,
        optimistic: OptimisticResponse?,
        failure: ResponseFailure?
    ) -> InvitationUI? {
        guard !isOrganizer(event, myUserId: myUserId), answerable.contains(event.viewerResponse) else { return nil }
        let phase = optimistic?.phase ?? .idle
        let shown: InvitationState = optimistic.map { $0.accept ? .accepted : .declined } ?? event.viewerResponse
        return InvitationUI(
            response: shown,
            canChange: notStarted(event, now: now, zone: zone) && phase != .saving,
            phase: phase,
            failure: failure
        )
    }

    /// Join state, or nil for an event with nothing to join (in person, no link).
    public static func join(_ event: CalendarEvent, now: Date, isBusy: Bool, error: JoinError?) -> JoinUI? {
        guard event.isSprout || event.isOnline || event.joinURL != nil else { return nil }
        let opensAt = event.start.addingTimeInterval(-CalendarEvent.joinLeadTime)
        let state: JoinState
        if event.isAllDay {
            state = .noTime
        } else if event.isJoinWindowOpen(at: now) {
            state = .open
        } else if now < opensAt {
            state = .tooEarly
        } else {
            state = .ended
        }
        return JoinUI(state: state, opensAt: event.isAllDay ? nil : opensAt, isBusy: isBusy, error: error)
    }

    /// "Message organizer" is offered to anyone but the organizer when the owner is known.
    public static func canMessageOrganizer(_ event: CalendarEvent, myUserId: String?) -> Bool {
        guard let owner = event.ownerId, !owner.isEmpty else { return false }
        return !isOrganizer(event, myUserId: myUserId)
    }

    /// Attendee rows. My row shows the optimistic answer; only employees get a milestone badge.
    public static func attendees(
        _ event: CalendarEvent,
        myUserId: String?,
        optimistic: OptimisticResponse?,
        milestones: MilestoneCalendar,
        today: CalendarDate
    ) -> [AttendeeRow] {
        event.attendees.map { attendee in
            let isEmployee = attendee.kind == .employee
            let isMe = isEmployee && myUserId != nil && attendee.ref == myUserId
            let response: InvitationState =
                if isMe, let optimistic { optimistic.accept ? .accepted : .declined } else { attendee.response }
            return AttendeeRow(
                id: attendee.id,
                userId: isEmployee ? attendee.ref : nil,
                name: attendee.displayName,
                email: attendee.email,
                response: response,
                celebration: isEmployee ? milestones.celebration(for: attendee.ref, on: today) : nil,
                isMe: isMe,
                isEmployee: isEmployee
            )
        }
    }
}

/// Payload-derived links are untrusted (11-pitfalls §15): only absolute http(s) URLs with a host.
public enum WebLinks {
    public static func isWebURL(_ url: URL?) -> Bool {
        guard let url, let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else { return false }
        return true
    }
}
