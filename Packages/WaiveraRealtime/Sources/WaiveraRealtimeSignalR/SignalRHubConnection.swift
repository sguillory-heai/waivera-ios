import Foundation
import SignalRClient
import WaiveraAPI
import WaiveraRealtime

/// Builds one-shot connections on the official SignalR Swift client. Automatic reconnect is
/// left off: `LiveRealtimeClient` owns retry, rejoin and resync.
public struct SignalRHubConnectionFactory: HubConnectionFactory {
    public init() {}

    public func makeConnection(
        url: URL,
        eventSignatures: [String: [HubArgumentKind]],
        accessToken: @escaping @Sendable () async throws -> String
    ) -> any WaiveraRealtime.HubConnection {
        var options = HttpConnectionOptions()
        options.accessTokenFactory = { try await accessToken() }
        options.logHandler = SilentLogHandler()
        options.logMessageContent = false
        let connection = HubConnectionBuilder()
            .withUrl(url: url.absoluteString, options: options)
            .withLogHandler(logHandler: SilentLogHandler())
            .withLogLevel(logLevel: .error)
            .build()
        return SignalRHubConnection(connection: connection, eventSignatures: eventSignatures)
    }
}

/// Adapts `SignalRClient.HubConnection` to `WaiveraRealtime.HubConnection`.
///
/// Every argument is bound as `AnyHashable` (see `AnyHashable+Decodable.swift`): the client
/// decodes objects through `Decodable` but hands scalars through untouched, and a typed binding
/// such as `String?` drops events whose argument is `null` (a removed reaction, an unread
/// receipt).
final class SignalRHubConnection: WaiveraRealtime.HubConnection {
    /// Methods whose completion carries a value; the rest are bound as void invocations.
    static let methodsWithResult: Set<String> = [
        ChatHubContract.Method.sendMessage,
        ChatHubContract.Method.getConnectionId,
        ChatHubContract.Method.getUserIdentifier,
    ]

    let invocations: AsyncStream<HubInvocation>
    private let continuation: AsyncStream<HubInvocation>.Continuation
    private let connection: SignalRClient.HubConnection
    private let eventSignatures: [String: [HubArgumentKind]]
    private let closed = ClosedSignal()

    init(connection: SignalRClient.HubConnection, eventSignatures: [String: [HubArgumentKind]]) {
        self.connection = connection
        self.eventSignatures = eventSignatures
        // Unbounded: the network bounds the producer, and a dropped message, reaction or
        // receipt would stay missing until the next REST refresh (IF-11).
        (invocations, continuation) = AsyncStream.makeStream(bufferingPolicy: .unbounded)
    }

    func start() async throws {
        let continuation = continuation
        let closed = closed
        for (target, kinds) in eventSignatures {
            await connection.registerHashable(target, arity: kinds.count) { arguments in
                continuation.yield(HubInvocation(target: target, arguments: arguments))
            }
        }
        await connection.onClosed { error in
            continuation.finish()
            closed.close(error)
        }
        do {
            try await connection.start()
        } catch {
            continuation.finish()
            closed.close(error)
            throw Self.startFailure(error)
        }
    }

    func stop() async {
        await connection.stop()
        continuation.finish()
        closed.close(nil)
    }

    func invoke(_ method: String, arguments: [JSONValue]) async throws -> JSONValue {
        do {
            if Self.methodsWithResult.contains(method) {
                return try await connection.invokeSpreading(method, arguments)
            }
            try await connection.invokeVoidSpreading(method, arguments)
            return .null
        } catch let error as SignalRError {
            throw Self.map(error)
        }
    }

    func send(_ method: String, arguments: [JSONValue]) async throws {
        do {
            try await connection.sendSpreading(method, arguments)
        } catch let error as SignalRError {
            throw Self.map(error)
        }
    }

    func waitUntilClosed() async -> (any Error)? {
        await closed.wait()
    }

    /// The client reports a rejected negotiate only as text ("Unexpected status code returned
    /// from negotiate '401'"). That one case is told apart so the token is refreshed once; every
    /// other start failure is a plain outage.
    static func startFailure(_ error: any Error) -> WaiveraError {
        String(describing: error).contains("'401'") ? .unauthorized : .realtimeUnavailable
    }

    private static func map(_ error: SignalRError) -> any Error {
        if case .invocationError(let message) = error { return HubInvocationError(message: message) }
        return WaiveraError.realtimeUnavailable
    }
}

/// The client logs payloads at debug level; nothing from the hub is logged (AGENTS.md safety).
struct SilentLogHandler: LogHandler {
    func log(logLevel: LogLevel, message: LogMessage, file: String, function: String, line: UInt) {}
}

/// Resolves every waiter once the connection has closed, including waiters that arrive late.
final class ClosedSignal: @unchecked Sendable {
    private struct State {
        var isClosed = false
        var error: (any Error)?
        var waiters: [CheckedContinuation<(any Error)?, Never>] = []
    }

    private let state = LockedValue(State())

    func close(_ error: (any Error)?) {
        let waiters = state.update { state -> [CheckedContinuation<(any Error)?, Never>] in
            guard !state.isClosed else { return [] }
            state.isClosed = true
            state.error = error
            defer { state.waiters.removeAll() }
            return state.waiters
        }
        for waiter in waiters { waiter.resume(returning: error) }
    }

    func wait() async -> (any Error)? {
        await withCheckedContinuation { continuation in
            let closedError: (any Error)?? = state.update { state in
                if state.isClosed { return .some(state.error) }
                state.waiters.append(continuation)
                return .none
            }
            if let closedError { continuation.resume(returning: closedError) }
        }
    }
}
