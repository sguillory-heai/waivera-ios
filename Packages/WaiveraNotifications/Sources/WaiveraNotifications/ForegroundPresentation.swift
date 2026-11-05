/// What the app knows when a push arrives while it is in the foreground.
public struct ForegroundContext: Equatable, Sendable {
    /// `true` when the data layer hides chat pushes for this payload's conversation
    /// (`ChatAlertsRepository.shouldPresentForegroundPush` returned `false`): the hub is
    /// connected and that conversation's timeline is on screen with the app active. The data
    /// layer owns that rule; this type only turns its answer and the settings into options.
    public var isConversationLive: Bool
    /// The same answer for the payload's thread: the hub is connected and that thread is on
    /// screen. Only a thread reply uses it (IF-02).
    public var isThreadLive: Bool
    /// Settings "In-app banners".
    public var inAppBannersEnabled: Bool
    /// Settings "Sound".
    public var soundEnabled: Bool
    /// The session is signed in. A push that reaches a signed-out device (an unregister that
    /// never reached the server) is someone else's message, so it is never shown.
    public var isSignedIn: Bool
    /// The hub is connected, so the app shows chat messages in its own banner: sprout_api's
    /// attention service sends the hub alert to the same people as the push.
    public var inAppAlertsLive: Bool

    public init(
        isConversationLive: Bool,
        inAppBannersEnabled: Bool,
        soundEnabled: Bool,
        isSignedIn: Bool,
        isThreadLive: Bool = false,
        inAppAlertsLive: Bool = false
    ) {
        self.isConversationLive = isConversationLive
        self.isThreadLive = isThreadLive
        self.inAppBannersEnabled = inAppBannersEnabled
        self.soundEnabled = soundEnabled
        self.isSignedIn = isSignedIn
        self.inAppAlertsLive = inAppAlertsLive
    }
}

/// How to present a foreground notification. Maps to `UNNotificationPresentationOptions`.
public struct PresentationDecision: Equatable, Sendable {
    public var showBanner: Bool
    public var showInList: Bool
    public var playSound: Bool

    public init(showBanner: Bool, showInList: Bool, playSound: Bool) {
        self.showBanner = showBanner
        self.showInList = showInList
        self.playSound = playSound
    }

    public static let suppressed = PresentationDecision(showBanner: false, showInList: false, playSound: false)
}

/// Foreground presentation, as chat apps do it: while the app is open the system banner and its
/// sound stay out of the way. A chat message whose surface is on screen shows nothing (AF-12,
/// IF-02); any other chat message shows in the app's own banner while the hub is connected,
/// so the system one is hidden. A disconnected hub never hides a message: it falls back to a
/// silent system banner. Pushes are silent in the foreground; the sound is for a phone in a
/// pocket. The icon badge is never set by a push.
public enum ForegroundPresentationPolicy {
    public static func decide(for payload: PushPayload, context: ForegroundContext) -> PresentationDecision {
        guard context.isSignedIn else { return .suppressed }
        if case .chat(let chat) = payload {
            if chat.isThreadReply ? context.isThreadLive : context.isConversationLive { return .suppressed }
            if context.inAppAlertsLive, context.inAppBannersEnabled { return .suppressed }
        }
        return PresentationDecision(showBanner: context.inAppBannersEnabled, showInList: true, playSound: false)
    }
}
