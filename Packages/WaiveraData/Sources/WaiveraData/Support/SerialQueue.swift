import Foundation
import WaiveraAPI

/// Runs async work one item at a time in submission order, so cache writes never land out
/// of order.
public final class SerialQueue: Sendable {
    private let tail = LockedValue<Task<Void, Never>?>(nil)

    public init() {}

    public func enqueue(_ work: @escaping @Sendable () async -> Void) {
        tail.update { tail in
            let previous = tail
            tail = Task {
                await previous?.value
                await work()
            }
        }
    }

    /// Waits for everything submitted so far.
    public func drain() async {
        await tail.get()?.value
    }
}
