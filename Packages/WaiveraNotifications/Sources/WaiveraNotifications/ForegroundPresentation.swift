/// What the app knows when a push arrives while it is in the foreground.
public struct ForegroundContext: Equatable, Sendable {
    public var isHubConnected: Bool
    /// The conversation on screen (router `visibleConversationID`), `nil` when none.
    public var visibleConversationID: Int?
    /// Settings "In-app banners".
    public var inAppBannersEnabled: Bool
    /// Settings "Sound".
    public var soundEnabled: Bool

    public init(isHubConnected: Bool, visibleConversationID: Int?, inAppBannersEnabled: Bool, soundEnabled: Bool) {
        self.isHubConnected = isHubConnected
        self.visibleConversationID = visibleConversationID
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

/// The foreground rule (PLAN.md parity fix, 09-push §2): a chat push is suppressed only when
/// the hub is connected AND that conversation is on screen, so a disconnected hub never hides
/// a message. The icon badge is never set by a push.
public enum ForegroundPresentationPolicy {
    public static func decide(for payload: PushPayload, context: ForegroundContext) -> PresentationDecision {
        if payload.isChat, context.isHubConnected, let conversationID = payload.conversationID,
            conversationID == context.visibleConversationID
        {
            return .suppressed
        }
        return PresentationDecision(
            showBanner: context.inAppBannersEnabled,
            showInList: true,
            playSound: context.inAppBannersEnabled && context.soundEnabled
        )
    }
}
