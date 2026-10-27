import Foundation
import WaiveraAPI

@testable import WaiveraRealtime

/// A scripted transport: each `start()` takes the next outcome; once the script runs out,
/// connections succeed and stay open until the test closes them.
final class FakeHubFactory: HubConnectionFactory, @unchecked Sendable {
    enum Outcome: Sendable {
        case fail
        /// The negotiate answered 401: the hub rejected the token.
        case unauthorized
        case connect
    }

    struct Call: Equatable, Sendable {
        var method: String
        var arguments: [JSONValue]
    }

    private let state = LockedValue(State())
    /// Runs inside the next `invoke` of a method, before it answers (then is cleared).
    let interleave = LockedValue<[String: @Sendable () async -> Void]>([:])

    private struct State {
        var script: [Outcome] = []
        var connections: [FakeHubConnection] = []
        var starts = 0
        var calls: [Call] = []
        var forcedRefreshes: [Bool] = []
        var results: [String: Result<JSONValue, HubInvocationError>] = [:]
    }

    init(script: [Outcome] = []) {
        state.update { $0.script = script }
    }

    var starts: Int { state.get().starts }
    var calls: [Call] { state.get().calls }
    var connections: [FakeHubConnection] { state.get().connections }
    var latest: FakeHubConnection? { state.get().connections.last }

    func calls(to method: String) -> [Call] { calls.filter { $0.method == method } }

    func setResult(_ result: Result<JSONValue, HubInvocationError>, for method: String) {
        state.update { $0.results[method] = result }
    }

    func makeConnection(
        url: URL,
        eventSignatures: [String: [HubArgumentKind]],
        accessToken: @escaping @Sendable () async throws -> String
    ) -> any HubConnection {
        let connection = FakeHubConnection(factory: self, accessToken: accessToken)
        state.update { $0.connections.append(connection) }
        return connection
    }

    func nextOutcome() -> Outcome {
        state.update { state in
            state.starts += 1
            return state.script.isEmpty ? .connect : state.script.removeFirst()
        }
    }

    func record(_ call: Call) -> Result<JSONValue, HubInvocationError> {
        state.update { state in
            state.calls.append(call)
            return state.results[call.method] ?? .success(.null)
        }
    }
}

final class FakeHubConnection: HubConnection, @unchecked Sendable {
    let invocations: AsyncStream<HubInvocation>
    private let continuation: AsyncStream<HubInvocation>.Continuation
    private unowned let factory: FakeHubFactory
    private let accessToken: @Sendable () async throws -> String
    private let closed = LockedValue<(isClosed: Bool, waiters: [CheckedContinuation<(any Error)?, Never>])>(
        (false, [])
    )
    private let token = LockedValue<String?>(nil)

    init(factory: FakeHubFactory, accessToken: @escaping @Sendable () async throws -> String) {
        self.factory = factory
        self.accessToken = accessToken
        (invocations, continuation) = AsyncStream.makeStream()
    }

    var usedToken: String? { token.get() }

    func start() async throws {
        let value = try await accessToken()
        token.update { $0 = value }
        switch factory.nextOutcome() {
        case .fail:
            close()
            throw WaiveraError.realtimeUnavailable
        case .unauthorized:
            close()
            throw WaiveraError.unauthorized
        case .connect:
            break
        }
    }

    func stop() async { close() }

    func invoke(_ method: String, arguments: [JSONValue]) async throws -> JSONValue {
        let hook = factory.interleave.update { $0.removeValue(forKey: method) }
        if let hook { await hook() }
        return try factory.record(.init(method: method, arguments: arguments)).get()
    }

    func send(_ method: String, arguments: [JSONValue]) async throws {
        _ = factory.record(.init(method: method, arguments: arguments))
    }

    func waitUntilClosed() async -> (any Error)? {
        await withCheckedContinuation { waiter in
            let alreadyClosed = closed.update { state -> Bool in
                if state.isClosed { return true }
                state.waiters.append(waiter)
                return false
            }
            if alreadyClosed { waiter.resume(returning: nil) }
        }
    }

    /// Server push.
    func emit(_ invocation: HubInvocation) {
        continuation.yield(invocation)
    }

    /// The server or network dropped the connection.
    func close() {
        let waiters = closed.update { state -> [CheckedContinuation<(any Error)?, Never>] in
            guard !state.isClosed else { return [] }
            state.isClosed = true
            defer { state.waiters = [] }
            return state.waiters
        }
        continuation.finish()
        for waiter in waiters { waiter.resume(returning: nil) }
    }
}

/// Counts token requests and whether each one was forced.
final class FakeTokenProvider: AuthTokenProvider, @unchecked Sendable {
    private let state = LockedValue<(token: String?, forced: [Bool])>(("token-1", []))

    var forced: [Bool] { state.get().forced }

    func signOut() { state.update { $0.token = nil } }

    func idToken(forceRefresh: Bool) async throws -> String? {
        state.update { state in
            state.forced.append(forceRefresh)
            return state.token
        }
    }
}

/// Never really sleeps; records requested delays and lets the test advance the wall clock.
final class InstantClock: WaiveraClock, @unchecked Sendable {
    private let state = LockedValue<(now: Date, sleeps: [Duration])>((Date(timeIntervalSince1970: 1_792_000_000), []))

    var now: Date { state.get().now }
    var sleeps: [Duration] { state.get().sleeps }

    func advance(by seconds: TimeInterval) {
        state.update { $0.now = $0.now.addingTimeInterval(seconds) }
    }

    func sleep(for duration: Duration) async throws {
        state.update { $0.sleeps.append(duration) }
        await Task.yield()
        try Task.checkCancellation()
    }
}

/// Polls until `condition` holds, failing after about two seconds of real time.
func eventually(
    _ description: String = "condition",
    _ condition: @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<2_000 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return false
}
