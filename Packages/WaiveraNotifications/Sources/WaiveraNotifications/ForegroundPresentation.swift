/// What the app knows when a push arrives while it is in the foreground.
public struct ForegroundContext: Equatable, Sendable {
    /// `true` when the data layer hides chat pushes for this payload's conversation
    /// (`ChatAlertsRepository.shouldPresentForegroundPush` returned `false`): the hub is
    /// connected and that conversation is on screen with the app active. The data layer owns
    /// that rule; this type only turns its answer and the settings into presentation options.
    public var isConversationLive: Bool
    /// Settings "In-app banners".
    public var inAppBannersEnabled: Bool
    /// Settings "Sound".
    public var soundEnabled: Bool

    public init(isConversationLive: Bool, inAppBannersEnabled: Bool, soundEnabled: Bool) {
        self.isConversationLive = isConversationLive
        self.inAppBannersEnabled = inAppBannersEnabled
        self.soundEnabled = soundEnabled
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
/// and only when the data layer reports their conversation live on screen, so a disconnected hub
/// never hides a message. The icon badge is never set by a push.
public enum ForegroundPresentationPolicy {
    public static func decide(for payload: PushPayload, context: ForegroundContext) -> PresentationDecision {
        if payload.isChat, context.isConversationLive {
            return .suppressed
        }
        return PresentationDecision(
            showBanner: context.inAppBannersEnabled,
            showInList: true,
            playSound: context.inAppBannersEnabled && context.soundEnabled
        )
    }
}
