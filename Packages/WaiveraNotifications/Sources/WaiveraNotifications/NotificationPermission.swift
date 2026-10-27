import Foundation

/// Mirrors `UNAuthorizationStatus` without importing UserNotifications.
public enum NotificationAuthorization: Equatable, Sendable {
    case notDetermined
    case denied
    case authorized
    case provisional
    case ephemeral
}

/// What Settings → Notifications shows about the system permission (09-push §9).
public enum SystemNotificationStatus: Equatable, Sendable {
    /// Not asked yet; Settings offers "Turn on notifications".
    case notAsked
    case on
    /// Provisional: notifications arrive quietly in Notification Center. Offer "Turn on alerts".
    case deliveredQuietly
    /// Denied: show a persistent note with a link to the system Settings app.
    case offInSystemSettings
}

/// Choices on the one-screen primer shown after first sign-in.
public enum PrimerChoice: Sendable {
    case enable
    case notNow
}

/// The authorization request a primer choice leads to.
public enum AuthorizationRequest: Equatable, Sendable {
    /// Alerts, sounds and badges; shows the system prompt.
    case full
    /// Quiet delivery with no prompt, so the person sees value before deciding.
    case provisional
}

public enum NotificationPermissionPolicy {
    /// The primer shows once, after first sign-in, only while the system has not been asked.
    /// It is never re-shown on later launches (UX research: do not re-ask every launch).
    public static func shouldShowPrimer(authorization: NotificationAuthorization, hasSeenPrimer: Bool) -> Bool {
        authorization == .notDetermined && !hasSeenPrimer
    }

    public static func request(for choice: PrimerChoice) -> AuthorizationRequest {
        switch choice {
        case .enable: .full
        case .notNow: .provisional
        }
    }

    public static func status(for authorization: NotificationAuthorization) -> SystemNotificationStatus {
        switch authorization {
        case .notDetermined: .notAsked
        case .authorized, .ephemeral: .on
        case .provisional: .deliveredQuietly
        case .denied: .offInSystemSettings
        }
    }

    /// Whether a push token should be registered with the server. A denied device gets no
    /// registration call (09-push §10); provisional devices do, since they still receive pushes.
    public static func allowsRegistration(_ authorization: NotificationAuthorization) -> Bool {
        switch authorization {
        case .authorized, .provisional, .ephemeral: true
        case .denied, .notDetermined: false
        }
    }
}

/// Remembers that the primer was shown, per install. A UI flag only, so UserDefaults is fine.
public struct PrimerSeenStore: Sendable {
    public static let key = "waivera.notificationPrimerSeen"

    private let suiteName: String?

    /// `suiteName` is for tests; the app uses the standard defaults.
    public init(suiteName: String? = nil) {
        self.suiteName = suiteName
    }

    public var hasSeen: Bool {
        defaults.bool(forKey: Self.key)
    }

    public func markSeen() {
        defaults.set(true, forKey: Self.key)
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }
}
