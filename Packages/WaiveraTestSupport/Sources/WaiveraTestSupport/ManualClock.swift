import Foundation
import WaiveraAPI

/// A clock that moves only when told to. Sleepers wake when `advance(by:)` passes their
/// deadline, so retries, debounces and typing expiry are testable without real waiting.
public final class ManualClock: WaiveraClock, @unchecked Sendable {
    private struct Sleeper {
        var deadline: Date
        var continuation: CheckedContinuation<Void, any Error>
    }

    private struct State {
        var now: Date
        var sleepers: [UUID: Sleeper] = [:]
    }

    private let state: LockedValue<State>

    public init(now: Date = DemoData.now) {
        state = LockedValue(State(now: now))
    }

    public var now: Date { state.get().now }

    /// Sleepers waiting for a future `advance`.
    public var pendingSleepers: Int { state.get().sleepers.count }

    public func sleep(for duration: Duration) async throws {
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        guard seconds > 0 else { return }
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let cancelled = state.update { state -> Bool in
                    if Task.isCancelled { return true }
                    state.sleepers[id] = Sleeper(
                        deadline: state.now.addingTimeInterval(seconds),
                        continuation: continuation
                    )
                    return false
                }
                if cancelled { continuation.resume(throwing: CancellationError()) }
            }
        } onCancel: {
            let sleeper = state.update { $0.sleepers.removeValue(forKey: id) }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Moves time forward and resumes every sleeper that is now due.
    public func advance(by seconds: TimeInterval) {
        let due = state.update { state -> [Sleeper] in
            state.now = state.now.addingTimeInterval(seconds)
            let ready = state.sleepers.filter { $0.value.deadline <= state.now }
            for id in ready.keys { state.sleepers[id] = nil }
            return ready.values.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due { sleeper.continuation.resume() }
    }
}
