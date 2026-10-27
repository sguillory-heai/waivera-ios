import Foundation

/// Keeps the visible order steady while the person is scrolled down (02 §9, "realtime
/// reorder without scroll jump"). At the top, rows reorder live, so a conversation with a new
/// message moves up at once. Scrolled down, rows keep their place and their content still
/// updates; conversations that would move or appear wait until the person returns to the top
/// or taps the "New activity" pill. Filter and search changes apply at once, since the person
/// asked for them.
struct InboxOrderHold: Sendable, Hashable {
    private(set) var heldOrder: [Int]?

    var isHolding: Bool { heldOrder != nil }

    /// Starts holding the given live order (the person scrolled away from the top).
    mutating func hold(_ liveOrder: [Int]) {
        if heldOrder == nil { heldOrder = liveOrder }
    }

    /// Re-takes the hold at the new live order (filter, search or refresh the person asked for).
    mutating func rebase(_ liveOrder: [Int]) {
        if heldOrder != nil { heldOrder = liveOrder }
    }

    mutating func release() { heldOrder = nil }

    /// The ids to show, in display order, and whether anything is waiting to move or appear.
    func arrange(_ liveOrder: [Int]) -> (order: [Int], hasPending: Bool) {
        guard let heldOrder else { return (liveOrder, false) }
        let live = Set(liveOrder)
        let kept = heldOrder.filter(live.contains)
        let keptSet = Set(kept)
        let waiting = liveOrder.contains { !keptSet.contains($0) }
        let reordered = liveOrder.filter(keptSet.contains) != kept
        return (kept, waiting || reordered)
    }
}
