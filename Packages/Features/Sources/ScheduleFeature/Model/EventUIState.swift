import Foundation
import WaiveraAPI
import WaiveraData
import WaiveraDesign

public enum EventUIState: Sendable, Hashable {
    case loading
    case notFound
    case error(WaiveraError)
    case loaded(EventDetailsUI)
}

/// The event screen, formatted in the schedule zone (07 §7).
public struct EventDetailsUI: Sendable, Hashable {
    public struct Person: Sendable, Hashable, Identifiable {
        public var id: String
        public var userId: String?
        public var name: String
        /// Under the name: the invite status for attendees.
        public var detail: String?
        public var celebration: ScheduleCelebration?
        /// The whole row for VoiceOver: name, status and celebration.
        public var accessibilityLabel: String
    }

    public var eventId: String
    public var title: String
    public var zoneNotice: String?
    public var ownerColor: RGBColor?
    public var organizer: Person?
    public var isOrganizer: Bool
    public var timePrimary: String
    public var timeSecondary: String?
    public var isOnline: Bool
    public var location: String?
    public var details: String?
    public var taskTitle: String?
    public var attendees: [Person]
    public var attendeeCount: String
    public var invitation: InvitationUI?
    /// "You're going." etc., or the "has started" note.
    public var invitationStatus: String?
    public var invitationFailure: String?
    public var join: JoinUI?
    /// Under the Join button: when it opens, that it ended, or why it failed.
    public var joinNote: String?
    public var joinError: String?
    public var canMessageOrganizer: Bool
    public var isOpeningChat: Bool
    public var chatError: String?
    /// A refresh failed; the saved copy is shown with this banner.
    public var refreshNotice: String?
}

/// An Undo offer for a just-chosen answer. Undo and the toast's dismissal pass it back, so a
/// toast replaced by a newer choice can neither undo nor commit the newer one.
public struct UndoOffer: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let token: Int
    public let accept: Bool
    public let message: String
}

/// A one-off request for the view to open a validated web link.
public struct OpenRequest: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let url: URL
}

/// A one-off request for the view to open a conversation.
public struct ConversationRequest: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let conversationId: Int
}
