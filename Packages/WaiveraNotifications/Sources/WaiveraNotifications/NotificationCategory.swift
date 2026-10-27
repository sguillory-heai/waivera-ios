/// Notification categories by meaning (UX research, PLAN.md). iOS categories and Android
/// channels use the same ids so both apps describe one taxonomy.
public enum NotificationMeaning: String, CaseIterable, Sendable {
    /// Direct message or @mention. High importance, Reply + Mark read.
    case messages
    /// Group chat activity. Default importance, Reply + Mark read.
    case groupActivity = "group_activity"
    /// A shift or event starting within the hour. High importance.
    case scheduleReminders = "schedule_reminders"
    /// A moved or cancelled shift or event. Default importance.
    case scheduleChanges = "schedule_changes"
    /// Milestones, announcements, low-priority roll-ups. Low importance, no actions.
    case digest

    /// The meaning of a received push. The server cannot yet tell a DM or mention from group
    /// chatter (it sends `CHAT_MESSAGE` for both), so every chat push is `messages` until it
    /// sends a meaning-based category (contract gap, see the report).
    public static func classify(_ payload: PushPayload, aps: PushPayload.APSInfo? = nil) -> NotificationMeaning {
        if let category = aps?.category, let meaning = NotificationMeaning(rawValue: category) {
            return meaning
        }
        switch payload {
        case .chat, .invalidChat, .call: return .messages
        case .meeting: return .scheduleChanges
        case .survey, .unknown: return .digest
        }
    }
}

/// Action identifiers. The `com.apple.*` values are UserNotifications' default and dismiss ids,
/// spelled out so the interpreter stays Foundation-only.
public enum NotificationActionID {
    public static let reply = "waivera.reply"
    public static let markRead = "waivera.markRead"
    public static let open = "com.apple.UNNotificationDefaultActionIdentifier"
    public static let dismiss = "com.apple.UNNotificationDismissActionIdentifier"
}

/// A notification action as data; the live target turns it into `UNNotificationAction`.
public struct NotificationActionDefinition: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case plain
        /// Inline text input (`UNTextInputNotificationAction`).
        case textInput(buttonTitleKey: String, placeholderKey: String)
    }

    public let identifier: String
    public let titleKey: String
    public let kind: Kind
    /// Requires the device to be unlocked (Reply and Mark read act on the account).
    public let requiresAuthentication: Bool

    public init(identifier: String, titleKey: String, kind: Kind, requiresAuthentication: Bool) {
        self.identifier = identifier
        self.titleKey = titleKey
        self.kind = kind
        self.requiresAuthentication = requiresAuthentication
    }
}

/// A `UNNotificationCategory` as data.
public struct NotificationCategoryDefinition: Equatable, Sendable {
    public let identifier: String
    public let meaning: NotificationMeaning
    public let actions: [NotificationActionDefinition]
    /// Shown instead of the body when previews are hidden on the lock screen.
    public let hiddenPreviewsPlaceholderKey: String

    public init(
        identifier: String,
        meaning: NotificationMeaning,
        actions: [NotificationActionDefinition],
        hiddenPreviewsPlaceholderKey: String
    ) {
        self.identifier = identifier
        self.meaning = meaning
        self.actions = actions
        self.hiddenPreviewsPlaceholderKey = hiddenPreviewsPlaceholderKey
    }
}

public enum NotificationCategories {
    /// The category sprout_api sets on iOS chat pushes today (push.md §2b).
    public static let serverChatCategory = "CHAT_MESSAGE"

    public static let chatActions: [NotificationActionDefinition] = [
        NotificationActionDefinition(
            identifier: NotificationActionID.reply,
            titleKey: "notification.action.reply",
            kind: .textInput(
                buttonTitleKey: "notification.action.reply.send",
                placeholderKey: "notification.action.reply.placeholder"
            ),
            requiresAuthentication: true
        ),
        NotificationActionDefinition(
            identifier: NotificationActionID.markRead,
            titleKey: "notification.action.markRead",
            kind: .plain,
            requiresAuthentication: true
        ),
    ]

    /// Every category the app registers. `CHAT_MESSAGE` is kept so today's server payloads get
    /// Reply and Mark read; the meaning ids are ready for the API to adopt.
    public static let all: [NotificationCategoryDefinition] = [
        NotificationCategoryDefinition(
            identifier: serverChatCategory,
            meaning: .messages,
            actions: chatActions,
            hiddenPreviewsPlaceholderKey: "notification.hidden.message"
        ),
        NotificationCategoryDefinition(
            identifier: NotificationMeaning.messages.rawValue,
            meaning: .messages,
            actions: chatActions,
            hiddenPreviewsPlaceholderKey: "notification.hidden.message"
        ),
        NotificationCategoryDefinition(
            identifier: NotificationMeaning.groupActivity.rawValue,
            meaning: .groupActivity,
            actions: chatActions,
            hiddenPreviewsPlaceholderKey: "notification.hidden.message"
        ),
        NotificationCategoryDefinition(
            identifier: NotificationMeaning.scheduleReminders.rawValue,
            meaning: .scheduleReminders,
            actions: [],
            hiddenPreviewsPlaceholderKey: "notification.hidden.schedule"
        ),
        NotificationCategoryDefinition(
            identifier: NotificationMeaning.scheduleChanges.rawValue,
            meaning: .scheduleChanges,
            actions: [],
            hiddenPreviewsPlaceholderKey: "notification.hidden.schedule"
        ),
        NotificationCategoryDefinition(
            identifier: NotificationMeaning.digest.rawValue,
            meaning: .digest,
            actions: [],
            hiddenPreviewsPlaceholderKey: "notification.hidden.digest"
        ),
    ]

    /// Notification Center groups by this id. Matches the server's `chat-{conversationId}`.
    public static func threadIdentifier(conversationID: Int) -> String {
        "chat-\(conversationID)"
    }
}
