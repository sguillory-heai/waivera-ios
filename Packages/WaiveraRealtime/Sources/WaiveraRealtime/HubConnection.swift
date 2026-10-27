import Foundation
import WaiveraAPI

/// One physical hub connection (one negotiate + WebSocket). The SignalR adapter in
/// `WaiveraRealtimeSignalR` implements it on Apple platforms; tests use a scripted fake.
/// A connection is used once: after it closes, `LiveRealtimeClient` makes a new one, so the
/// transport never runs its own automatic reconnect.
public protocol HubConnection: Sendable {
    /// Server-to-client invocations for every event in `ChatHubContract.Event.signatures`.
    var invocations: AsyncStream<HubInvocation> { get }

    func start() async throws
    func stop() async
    /// Waits for the hub method's completion and returns its result (`.null` for void).
    func invoke(_ method: String, arguments: [JSONValue]) async throws -> JSONValue
    /// Fire-and-forget, no completion.
    func send(_ method: String, arguments: [JSONValue]) async throws
    /// Returns once the connection has closed, with the error that closed it, if any.
    func waitUntilClosed() async -> (any Error)?
}

public protocol HubConnectionFactory: Sendable {
    /// `accessToken` is called on every negotiate; it returns the Firebase ID token.
    func makeConnection(
        url: URL,
        eventSignatures: [String: [HubArgumentKind]],
        accessToken: @escaping @Sendable () async throws -> String
    ) -> any HubConnection
}

/// A `HubException` raised by the server for an invocation; the message is used only to
/// pick a `WaiveraError` and is never shown.
public struct HubInvocationError: Error, Equatable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }

    public var waiveraError: WaiveraError {
        let text = message.lowercased()
        if text.contains("archived") { return .channelArchived }
        if text.contains("read-only") || text.contains("cannot post") { return .channelReadOnly }
        if text.contains("not authenticated") || text.contains("unauthenticated") { return .unauthorized }
        if text.contains("not a participant") || text.contains("not an active participant")
            || text.contains("access denied")
        {
            return .forbidden
        }
        if text.contains("does not exist") || text.contains("unavailable") { return .notFound }
        return .invalidRequest
    }
}
