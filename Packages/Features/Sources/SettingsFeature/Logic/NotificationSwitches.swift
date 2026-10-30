import Foundation
import WaiveraData
import WaiveraNotifications

/// Notification switches by meaning (PLAN.md categories, UX research), stored in the flags
/// `NotificationPreferences` has today.
///
/// Core stores the nine Expo flags, which are also the server's registration fields. Until it
/// stores one flag per meaning (docs/requests/feature-profile-settings.md, request 4), the
/// meanings map onto those flags the same way Android sends them to the server:
/// - Direct messages and mentions: `mentions` and `activeCalls`;
/// - Group chat activity: `reactions` (the only group-only flag);
/// - `chatMessages` is on while either meaning is on, so the server keeps sending chat pushes.
///
/// Schedule reminders, schedule changes and the digest have no flag yet and no push behind them
/// (gap G-07), so they are not offered rather than shown as switches that do nothing.
public enum NotificationSwitches {
    /// The meanings the screen offers today, in display order.
    public static let offered: [NotificationMeaning] = [.messages, .groupActivity]

    public static func isSupported(_ meaning: NotificationMeaning) -> Bool {
        offered.contains(meaning)
    }

    public static func isOn(_ meaning: NotificationMeaning, in preferences: NotificationPreferences) -> Bool {
        switch meaning {
        case .messages: preferences.mentions
        case .groupActivity: preferences.reactions
        case .scheduleReminders, .scheduleChanges, .digest: true
        }
    }

    /// Writes one meaning. Unsupported meanings leave the preferences unchanged.
    public static func set(
        _ meaning: NotificationMeaning,
        to isOn: Bool,
        in preferences: inout NotificationPreferences
    ) {
        switch meaning {
        case .messages:
            preferences.mentions = isOn
            preferences.activeCalls = isOn
        case .groupActivity:
            preferences.reactions = isOn
        case .scheduleReminders, .scheduleChanges, .digest:
            return
        }
        preferences.chatMessages = preferences.mentions || preferences.reactions
    }
}

/// Why the category, preview and in-app switches are dimmed, if they are.
public enum NotificationSwitchBlock: Equatable, Sendable {
    /// The push master switch is off.
    case pushOff
    /// iOS blocks every notification from the app; the switches cannot fix that.
    case systemOff
}

extension NotificationSwitches {
    /// The dependent switches are dimmed, not changed, while push is off (08 §8) or iOS blocks the
    /// app (Android UI2-24): a switch reading On must never promise a notification. `nil` when
    /// they are live. Quiet delivery and "not asked yet" still deliver, so they block nothing.
    public static func block(pushEnabled: Bool, system: SystemNotificationStatus) -> NotificationSwitchBlock? {
        if system == .offInSystemSettings { return .systemOff }
        return pushEnabled ? nil : .pushOff
    }
}
