import Foundation
import WaiveraAPI
import WaiveraData

/// Failure and latency controls shared by every fake: set a failure to drive the error
/// state, a latency (on the fake's clock) to hold the loading state.
public struct FakeControls: Sendable {
    public var failure: WaiveraError?
    public var latency: Duration

    public init(failure: WaiveraError? = nil, latency: Duration = .zero) {
        self.failure = failure
        self.latency = latency
    }
}

/// A controllable `Resource` stream. `refresh()` goes through loading to loaded or failed
/// like a live repository, keeping the previous value on failure.
public final class FakeResource<Value: Sendable>: Sendable {
    private struct State {
        var value: Value?
        var controls: FakeControls
        var refreshCount = 0
    }

    private let state: LockedValue<State>
    private let cell = StateCell(Resource<Value>())
    private let clock: any WaiveraClock

    public init(_ value: Value?, controls: FakeControls = FakeControls(), clock: any WaiveraClock) {
        state = LockedValue(State(value: value, controls: controls))
        self.clock = clock
    }

    public func stream() -> AsyncStream<Resource<Value>> { cell.stream() }
    public var current: Resource<Value> { cell.current }
    public var value: Value? { state.get().value }
    public var refreshCount: Int { state.get().refreshCount }

    public func setControls(_ controls: FakeControls) {
        state.update { $0.controls = controls }
    }

    /// Replaces the server-side value; shown at once when a load already completed.
    public func setValue(_ value: Value?) {
        state.update { $0.value = value }
        cell.update { resource in
            if resource.phase == .loaded { resource.value = value }
        }
    }

    /// Changes the value in place, as an action or a realtime event would.
    public func mutate(_ transform: (inout Value) -> Void) {
        let next = state.update { state -> Value? in
            guard var value = state.value else { return nil }
            transform(&value)
            state.value = value
            return value
        }
        guard let next else { return }
        cell.update { resource in
            if resource.value != nil || resource.phase == .loaded { resource.value = next }
        }
    }

    public func refresh() async {
        let controls = state.update { state -> FakeControls in
            state.refreshCount += 1
            return state.controls
        }
        cell.update { $0.phase = .loading }
        if controls.latency > .zero { try? await clock.sleep(for: controls.latency) }
        let latest = state.get()
        if let failure = latest.controls.failure {
            cell.update { $0.phase = .failed(failure) }
        } else {
            cell.set(Resource(value: latest.value, phase: .loaded, updatedAt: clock.now))
        }
    }

    /// Back to idle with no value (sign-out).
    public func reset() {
        cell.set(Resource())
    }
}

/// A log of calls a fake received, for assertions.
public final class CallLog: Sendable {
    private let entries = LockedValue<[String]>([])

    public init() {}

    public var all: [String] { entries.get() }

    public func record(_ entry: String) {
        entries.update { $0.append(entry) }
    }

    public func count(_ prefix: String) -> Int {
        all.filter { $0.hasPrefix(prefix) }.count
    }
}
