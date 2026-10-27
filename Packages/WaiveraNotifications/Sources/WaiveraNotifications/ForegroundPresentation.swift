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

    public init(
        isConversationLive: Bool,
        inAppBannersEnabled: Bool,
        soundEnabled: Bool,
        isSignedIn: Bool,
        isThreadLive: Bool = false
    ) {
        self.isConversationLive = isConversationLive
        self.isThreadLive = isThreadLive
        self.inAppBannersEnabled = inAppBannersEnabled
        self.soundEnabled = soundEnabled
        self.isSignedIn = isSignedIn
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

/// Foreground presentation (PLAN.md parity fix, 09-push §2). Only chat pushes are ever hidden,
/// and only when the data layer reports the surface they belong to live on screen: the
/// conversation's timeline for a root message, the thread for a reply (AF-12, IF-02). A
/// disconnected hub never hides a message. The icon badge is never set by a push.
public enum ForegroundPresentationPolicy {
    public static func decide(for payload: PushPayload, context: ForegroundContext) -> PresentationDecision {
        guard context.isSignedIn else { return .suppressed }
        if case .chat(let chat) = payload, chat.isThreadReply ? context.isThreadLive : context.isConversationLive {
            return .suppressed
        }
        return PresentationDecision(
            showBanner: context.inAppBannersEnabled,
            showInList: true,
            playSound: context.inAppBannersEnabled && context.soundEnabled
        )
    }
}
