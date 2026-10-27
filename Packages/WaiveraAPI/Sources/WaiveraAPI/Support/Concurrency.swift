import Foundation

/// Wall clock and sleeping, injectable so tests and demo mode are deterministic.
public protocol WaiveraClock: Sendable {
    var now: Date { get }
    func sleep(for duration: Duration) async throws
}

public struct SystemClock: WaiveraClock {
    public init() {}
    public var now: Date { Date() }
    public func sleep(for duration: Duration) async throws {
        try await Task.sleep(for: duration)
    }
}

/// A lock-protected box for small pieces of state shared across isolation domains.
/// (`Mutex` needs iOS 18; the app supports iOS 17.)
public final class LockedValue<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    public init(_ value: Value) {
        self.value = value
    }

    public func get() -> Value {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    @discardableResult
    public func update<Result>(_ body: (inout Value) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

/// Multicasts values to any number of `AsyncStream` subscribers. Each new subscriber first
/// receives the current value (when `replays` is true), so a screen that subscribes late
/// still renders the latest state. Streams finish when the subscriber's task is cancelled.
public final class AsyncBroadcaster<Value: Sendable>: @unchecked Sendable {
    private struct State {
        var current: Value?
        var continuations: [UUID: AsyncStream<Value>.Continuation] = [:]
    }

    private let state: LockedValue<State>
    private let replays: Bool
    private let keepsEveryValue: Bool

    /// Starts with `initial` as the current value (which may itself be `nil` for optional values).
    /// A slow subscriber sees only the newest 64 values unless `keepsEveryValue` is set, which
    /// event streams (every hub event matters, IF-11) use; state streams only need the latest.
    public init(initial: Value, replays: Bool = true, keepsEveryValue: Bool = false) {
        state = LockedValue(State(current: .some(initial)))
        self.replays = replays
        self.keepsEveryValue = keepsEveryValue
    }

    /// Starts with no current value; subscribers wait for the first `send`.
    public init(replays: Bool = true, keepsEveryValue: Bool = false) {
        state = LockedValue(State(current: nil))
        self.replays = replays
        self.keepsEveryValue = keepsEveryValue
    }

    public var current: Value? { state.get().current }

    public func stream() -> AsyncStream<Value> {
        let (stream, continuation) = AsyncStream<Value>.makeStream(
            bufferingPolicy: keepsEveryValue ? .unbounded : .bufferingNewest(64)
        )
        let id = UUID()
        let replay: Value? = state.update { state in
            state.continuations[id] = continuation
            return replays ? state.current : nil
        }
        if let replay { continuation.yield(replay) }
        continuation.onTermination = { [weak self] _ in
            self?.state.update { state in _ = state.continuations.removeValue(forKey: id) }
        }
        return stream
    }

    public func send(_ value: Value) {
        let targets = state.update { state in
            state.current = value
            return Array(state.continuations.values)
        }
        for continuation in targets { continuation.yield(value) }
    }

    /// Applies `transform` to the current value atomically and broadcasts the result.
    @discardableResult
    public func modify(_ transform: (inout Value) -> Void) -> Value? {
        let (value, targets): (Value?, [AsyncStream<Value>.Continuation]) = state.update { state in
            guard var value = state.current else { return (nil, []) }
            transform(&value)
            state.current = value
            return (value, Array(state.continuations.values))
        }
        if let value {
            for continuation in targets { continuation.yield(value) }
        }
        return value
    }

    public func finish() {
        let targets = state.update { state in
            let values = Array(state.continuations.values)
            state.continuations.removeAll()
            return values
        }
        for continuation in targets { continuation.finish() }
    }
}
