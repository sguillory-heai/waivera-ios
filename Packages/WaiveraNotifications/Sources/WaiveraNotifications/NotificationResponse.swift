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

/// Routes notification taps exactly once, and holds one tap made before sign-in finished so it
/// opens after authentication (09-push §7). A later tap replaces an earlier held one.
public struct NotificationTapRouter: Sendable {
    /// Remembered response keys; the oldest is dropped beyond this.
    public static let capacity = 50

    private var processed: [String] = []
    public private(set) var pending: Destination?

    public init() {}

    /// `key` identifies one delivery of one response (request id + action id).
    /// Returns the destination to open now, or `nil`.
    public mutating func handle(key: String, destination: Destination?, isAuthenticated: Bool) -> Destination? {
        guard !processed.contains(key) else { return nil }
        remember(key)
        guard let destination else { return nil }
        guard isAuthenticated else {
            pending = destination
            return nil
        }
        return destination
    }

    /// Call when the session becomes signed in. Returns the held destination once.
    public mutating func didAuthenticate() -> Destination? {
        defer { pending = nil }
        return pending
    }

    /// Sign-in failed or was abandoned: drop the held tap so the user lands on the default tab.
    public mutating func discardPending() {
        pending = nil
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

    public init(key: String, actionIdentifier: String, payload: PushPayload, userText: String?) {
        self.key = key
        self.actionIdentifier = actionIdentifier
        self.payload = payload
        self.userText = userText
    }

    public var action: NotificationResponseAction {
        NotificationResponseInterpreter.interpret(
            actionIdentifier: actionIdentifier,
            payload: payload,
            userText: userText
        )
    }
}
