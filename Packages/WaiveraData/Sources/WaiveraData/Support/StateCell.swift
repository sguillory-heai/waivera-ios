import Foundation
import WaiveraAPI

/// A value plus its subscribers, for repositories: every write broadcasts, every new
/// subscriber gets the current value first.
public final class StateCell<Value: Sendable>: Sendable {
    private let broadcaster: AsyncBroadcaster<Value>
    private let value: LockedValue<Value>

    public init(_ initial: Value) {
        broadcaster = AsyncBroadcaster(initial: initial)
        value = LockedValue(initial)
    }

    public var current: Value { value.get() }

    public func stream() -> AsyncStream<Value> { broadcaster.stream() }

    public func set(_ newValue: Value) {
        update { $0 = newValue }
    }

    /// Applies `transform` atomically and broadcasts the result.
    @discardableResult
    public func update(_ transform: (inout Value) -> Void) -> Value {
        // Broadcast under the lock so subscribers see writes in order.
        value.update { current -> Value in
            transform(&current)
            broadcaster.send(current)
            return current
        }
    }
}
