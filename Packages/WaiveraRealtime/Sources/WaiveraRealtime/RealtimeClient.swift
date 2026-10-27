import Foundation
import WaiveraAPI

/// Connection state shown to the user as a quiet banner, never as a blocking error.
public enum ConnectionState: Equatable, Sendable {
    /// Not running: signed out, backgrounded, or offline.
    case disconnected
    case connecting
    case connected
    /// Waiting `delay` before reconnect attempt number `attempt`.
    case reconnecting(attempt: Int, delay: Duration)
}

/// What screens observe. `epoch` increases on every successful connect, so a screen or
/// repository can treat a new epoch as "groups rejoined, resync now" (05 §1).
public struct RealtimeStatus: Equatable, Sendable {
    public var state: ConnectionState
    public var epoch: Int

    public init(state: ConnectionState, epoch: Int) {
        self.state = state
        self.epoch = epoch
    }

    public static let initial = RealtimeStatus(state: .disconnected, epoch: 0)

    public var isConnected: Bool { state == .connected }
}

/// `SendMessage(conversationId, messageText, doc, parentMessageId, clientMessageId, attachmentUrl)`.
public struct HubSendMessage: Sendable, Equatable {
    public var conversationId: Int
    public var text: String
    public var doc: JSONValue?
    public var parentMessageId: Int?
    public var clientMessageId: String?
    public var attachmentUrl: String?

    public init(
        conversationId: Int,
        text: String,
        doc: JSONValue?,
        parentMessageId: Int?,
        clientMessageId: String?,
        attachmentUrl: String? = nil
    ) {
        self.conversationId = conversationId
        self.text = text
        self.doc = doc
        self.parentMessageId = parentMessageId
        self.clientMessageId = clientMessageId
        self.attachmentUrl = attachmentUrl
    }

    var arguments: [JSONValue] {
        [
            .number(Double(conversationId)), .string(text), doc ?? .null,
            parentMessageId.map { .number(Double($0)) } ?? .null,
            clientMessageId.map(JSONValue.string) ?? .null,
            attachmentUrl.map(JSONValue.string) ?? .null,
        ]
    }
}

/// The app's only door to the chat hub. Transport only: cache writes belong in repositories.
/// The connection's identity is (signed-in user, hub URL); preference changes and token
/// refreshes never rebuild it (05 §1).
public protocol RealtimeClient: Sendable {
    /// Replays the current status, then every change.
    func statuses() -> AsyncStream<RealtimeStatus>
    var currentStatus: RealtimeStatus { get }
    /// Typed events from the live connection (not replayed). Message events are de-duplicated.
    func events() -> AsyncStream<ChatHubEvent>

    /// The session started: connect and keep reconnecting while foregrounded and online.
    func start() async
    /// The session ended: disconnect and forget joined groups.
    func stop() async
    /// Foreground-only: background stops the connection, foreground reconnects.
    func setForeground(_ isForeground: Bool) async
    func setNetworkAvailable(_ isAvailable: Bool) async
    /// Manual retry from the "Reconnecting" banner: skips the current backoff wait.
    func retryNow() async

    /// Reference-counted group membership; joined (again) whenever the hub connects.
    func join(conversationId: Int) async
    func leave(conversationId: Int) async

    /// Throws `.realtimeUnavailable` when not connected so the caller can use REST.
    func sendMessage(_ message: HubSendMessage) async throws -> MessageSendResponse
    /// Fire-and-forget; silently skipped when not connected.
    func sendTypingStatus(conversationId: Int, isTyping: Bool) async
    func markAsRead(conversationId: Int) async throws
    /// Hub-only (gap G-01); throws `.realtimeUnavailable` when not connected.
    func sendReaction(messageId: Int, reactionType: String) async throws
}
