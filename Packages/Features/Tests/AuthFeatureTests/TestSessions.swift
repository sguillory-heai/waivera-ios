import Foundation
import WaiveraAPI
import WaiveraData

@testable import AuthFeature

/// A session the test drives step by step: it records every call, answers sign-in and password
/// change with a scripted outcome, and never changes state unless the test says so (like the
/// live session, whose state moves through `states()` after Firebase answers).
final class ScriptedSession: SessionRepository, @unchecked Sendable {
    enum Outcome: Sendable {
        case succeed
        case fail(WaiveraError)
        /// Suspends until the calling task is cancelled.
        case hold
    }

    private let cell: StateCell<SessionState>
    private let log = LockedValue<[String]>([])
    let signInOutcome = LockedValue(Outcome.succeed)
    let changeOutcome = LockedValue(Outcome.succeed)
    /// The state `retryBootstrap` moves to after `.bootstrapping`; unchanged when `nil`.
    let retryResult = LockedValue<SessionState?>(nil)
    let resetOutcome = LockedValue(Outcome.succeed)

    init(_ state: SessionState = .signedOut(nil)) {
        cell = StateCell(state)
    }

    var calls: [String] { log.get() }

    func set(_ state: SessionState) { cell.set(state) }

    func states() -> AsyncStream<SessionState> { cell.stream() }
    var currentState: SessionState { cell.current }
    func start() async { record("start") }

    func signIn(email: String, password: String) async throws {
        // Records the exact values sent, so tests can check trimming. Never done in app code.
        record("signIn:\(email):\(password)")
        try await perform(signInOutcome.get())
    }

    func changePassword(current: String, new: String) async throws {
        record("changePassword:\(current):\(new)")
        try await perform(changeOutcome.get())
    }

    func retryBootstrap() async {
        record("retryBootstrap")
        cell.set(.bootstrapping)
        if let next = retryResult.get() { cell.set(next) }
    }

    func signOut() async {
        record("signOut")
        cell.set(.signedOut(nil))
    }

    private func record(_ call: String) {
        log.update { $0.append(call) }
    }

    private func perform(_ outcome: Outcome) async throws {
        switch outcome {
        case .succeed: return
        case .fail(let error): throw error
        case .hold: try await Task.sleep(for: .seconds(3600))
        }
    }
}

extension ScriptedSession {
    func sendPasswordReset(email: String) async throws {
        record("reset:\(email)")
        try await perform(resetOutcome.get())
    }
}

/// Waits (yielding, then briefly sleeping) until `condition` holds or about a second passes.
@MainActor
func eventually(_ condition: @MainActor () -> Bool) async -> Bool {
    for attempt in 0..<200 {
        if condition() { return true }
        if attempt < 20 {
            await Task.yield()
        } else {
            try? await Task.sleep(for: .milliseconds(5))
        }
    }
    return condition()
}

extension LockedValue {
    func set(_ newValue: Value) {
        update { $0 = newValue }
    }
}
