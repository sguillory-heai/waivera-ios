import Foundation
import WaiveraDesign

/// What each notification category is for, in the order Settings lists them. Ids match the
/// categories by meaning in PLAN.md (`NotificationMeaning` in WaiveraNotifications) and the
/// Android primer, so both apps explain the same five kinds.
public enum PrimerCategory: String, CaseIterable, Sendable {
    case messages
    case groupActivity = "group_activity"
    case scheduleReminders = "schedule_reminders"
    case scheduleChanges = "schedule_changes"
    case digest

    public var systemImage: String {
        switch self {
        case .messages: "bubble.left.and.bubble.right.fill"
        case .groupActivity: "person.3.fill"
        case .scheduleReminders: "alarm.fill"
        case .scheduleChanges: "calendar.badge.clock"
        case .digest: "sun.max.fill"
        }
    }

    public var title: String {
        switch self {
        case .messages: AuthStrings.primerMessagesTitle
        case .groupActivity: AuthStrings.primerGroupTitle
        case .scheduleReminders: AuthStrings.primerRemindersTitle
        case .scheduleChanges: AuthStrings.primerChangesTitle
        case .digest: AuthStrings.primerDigestTitle
        }
    }

    public var detail: String {
        switch self {
        case .messages: AuthStrings.primerMessagesBody
        case .groupActivity: AuthStrings.primerGroupBody
        case .scheduleReminders: AuthStrings.primerRemindersBody
        case .scheduleChanges: AuthStrings.primerChangesBody
        case .digest: AuthStrings.primerDigestBody
        }
    }
}

/// One kind of notification the primer explains. The primer groups the five categories into the
/// three kinds people recognise (messages, schedule, digest) so it fits a small phone; Settings
/// lists each category separately (Android `PrimerKinds`).
public enum PrimerKind: String, CaseIterable, Sendable {
    case messages
    case schedule
    case digest

    public var categories: [PrimerCategory] {
        switch self {
        case .messages: [.messages, .groupActivity]
        case .schedule: [.scheduleReminders, .scheduleChanges]
        case .digest: [.digest]
        }
    }

    /// The tile's meaning tint: people and conversations, the schedule, announcements.
    public var tone: TileTone {
        switch self {
        case .messages: .brand
        case .schedule: .teal
        case .digest: .amber
        }
    }

    public var systemImage: String {
        switch self {
        case .messages: "bubble.left.and.bubble.right.fill"
        case .schedule: "calendar"
        case .digest: "megaphone.fill"
        }
    }

    public var title: String {
        switch self {
        case .messages: AuthStrings.primerMessagesTitle
        case .schedule: AuthStrings.primerScheduleTitle
        case .digest: AuthStrings.primerDigestTitle
        }
    }

    public var detail: String {
        switch self {
        case .messages: AuthStrings.primerMessagesBody
        case .schedule: AuthStrings.primerScheduleBody
        case .digest: AuthStrings.primerDigestBody
        }
    }
}
