import Foundation
import WaiveraAPI

/// Lazily created `StateCell`s by key, reachable without hopping onto the owning actor so
/// stream accessors can stay synchronous.
public final class CellRegistry<Key: Hashable & Sendable, Value: Sendable>: Sendable {
    private let cells = LockedValue<[Key: StateCell<Value>]>([:])
    private let initial: Value

    public init(initial: Value) {
        self.initial = initial
    }

    public func cell(_ key: Key) -> StateCell<Value> {
        cells.update { cells in
            if let cell = cells[key] { return cell }
            let cell = StateCell(initial)
            cells[key] = cell
            return cell
        }
    }

    /// Resets every cell to the initial value (sign-out) without dropping subscribers.
    public func resetAll() {
        for cell in cells.get().values { cell.set(initial) }
    }
}
