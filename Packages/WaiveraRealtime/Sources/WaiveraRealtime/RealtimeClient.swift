import Foundation

/// Connection state shown to the user as a quiet banner, never as a blocking error.
public enum ConnectionState: Equatable, Sendable {
    case disconnected
    case connecting
    case connected
    /// Waiting `delay` before reconnect attempt number `attempt`.
    case reconnecting(attempt: Int, delay: Duration)
}

/// The app's only door to the chat hub. Implementations own retry with
/// `ReconnectPolicy` and must rejoin open conversations and resync over REST
/// after every reconnect, because messages sent while offline are not replayed.
public protocol RealtimeClient: Sendable {
    var states: AsyncStream<ConnectionState> { get }

    /// Raw JSON payloads for a hub event, delivered while connected.
    func events(named eventName: String) -> AsyncStream<Data>

    func invoke(_ method: String, arguments: [any Encodable & Sendable]) async throws

    func connect() async throws

    func disconnect() async
}
