import Foundation
import WaiveraRouting

/// What to do with a tap or an action button on a notification.
public enum NotificationResponseAction: Equatable, Sendable {
    case open(Destination)
    case reply(conversationID: Int, threadRootMessageID: Int?, text: String)
    case markRead(conversationID: Int, messageID: Int?)
    /// Dismissed, or a tap that should leave the app where it opens.
    case none
}

public enum NotificationResponseInterpreter {
    /// Longest inline reply accepted; longer text is trimmed rather than rejected.
    public static let maxReplyLength = 4_000

    public static func interpret(
        actionIdentifier: String,
        payload: PushPayload,
        userText: String? = nil
    ) -> NotificationResponseAction {
        switch actionIdentifier {
        case NotificationActionID.dismiss:
            return .none
        case NotificationActionID.reply:
            guard case .chat(let chat) = payload else { return open(payload) }
            let text = (userText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return .none }
            return .reply(
                conversationID: chat.conversationID,
                threadRootMessageID: chat.threadRootMessageID,
                text: String(text.prefix(maxReplyLength))
            )
        case NotificationActionID.markRead:
            guard case .chat(let chat) = payload else { return .none }
            return .markRead(conversationID: chat.conversationID, messageID: chat.messageID)
        default:
            return open(payload)
        }
    }

    private static func open(_ payload: PushPayload) -> NotificationResponseAction {
        payload.destination.map(NotificationResponseAction.open) ?? .none
    }
}

/// Whether a notification response belongs to the person signed in now (IS-07). Chat pushes
/// carry no recipient id, so the binding is by time: a notification delivered before this
/// person first signed in on this device was meant for whoever used it before, and a reply,
/// Mark read or held tap from it is dropped instead of acting as the new account.
public enum NotificationAccountPolicy {
    /// Allowance for the notification date and the sign-in time coming from different clocks.
    public static let tolerance: TimeInterval = 2

    public static func belongsToCurrentAccount(deliveredAt: Date?, accountSince: Date?) -> Bool {
        guard let deliveredAt, let accountSince else { return true }
        return deliveredAt >= accountSince.addingTimeInterval(-tolerance)
    }
}

/// Routes notification taps exactly once, and holds one tap made before sign-in finished so it
/// opens after authentication (09-push §7). A later tap replaces an earlier held one. A held tap
/// opens only for the account it was delivered to (IS-07).
public struct NotificationTapRouter: Sendable {
    /// Remembered response keys; the oldest is dropped beyond this.
    public static let capacity = 50

    private var processed: [String] = []
    private var held: (destination: Destination, deliveredAt: Date?)?

    public init() {}

    public var pending: Destination? { held?.destination }

    /// `key` identifies one delivery of one response (request id + action id); `deliveredAt`
    /// is when its notification arrived. Returns the destination to open now, or `nil`.
    public mutating func handle(
        key: String,
        destination: Destination?,
        isAuthenticated: Bool,
        deliveredAt: Date? = nil
    ) -> Destination? {
        guard !processed.contains(key) else { return nil }
        remember(key)
        guard let destination else { return nil }
        guard isAuthenticated else {
            held = (destination, deliveredAt)
            return nil
        }
        return destination
    }

    /// Call when the session becomes signed in. Returns the held destination once, unless it
    /// was delivered before `accountSince` (someone else's notification).
    public mutating func didAuthenticate(accountSince: Date? = nil) -> Destination? {
        defer { held = nil }
        guard let held,
            NotificationAccountPolicy.belongsToCurrentAccount(deliveredAt: held.deliveredAt, accountSince: accountSince)
        else { return nil }
        return held.destination
    }

    /// Sign-in failed or was abandoned, or the session ended: drop the held tap so the user
    /// lands on the default tab.
    public mutating func discardPending() {
        held = nil
    }

    private mutating func remember(_ key: String) {
        processed.append(key)
        if processed.count > Self.capacity {
            processed.removeFirst(processed.count - Self.capacity)
        }
    }
}

/// One delivered notification response, already reduced to Sendable values by the live delegate.
public struct NotificationResponseEvent: Equatable, Sendable {
    /// Request identifier plus action identifier; dedupes repeated deliveries.
    public let key: String
    public let actionIdentifier: String
    public let payload: PushPayload
    public let userText: String?
    /// When the notification was delivered (`UNNotification.date`), for the account check.
    public let deliveredAt: Date?

    public init(key: String, actionIdentifier: String, payload: PushPayload, userText: String?, deliveredAt: Date? = nil) {
        self.key = key
        self.actionIdentifier = actionIdentifier
        self.payload = payload
        self.userText = userText
        self.deliveredAt = deliveredAt
    }

    /// Whether this response may act for the person signed in since `accountSince`.
    public func belongsToAccount(since accountSince: Date?) -> Bool {
        NotificationAccountPolicy.belongsToCurrentAccount(deliveredAt: deliveredAt, accountSince: accountSince)
    }

    public var action: NotificationResponseAction {
        NotificationResponseInterpreter.interpret(
            actionIdentifier: actionIdentifier,
            payload: payload,
            userText: userText
        )
    }
}
