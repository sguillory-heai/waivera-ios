import Foundation
import WaiveraAPI
import WaiveraData

/// Remembers which schedule range each event was last seen in, so the event screen watches that
/// feed instead of searching. `CalendarRepository` has no single-event call yet
/// (docs/requests/schedule.md item 1); this is the stand-in. Bounded, least recently used out first.
public final class EventRangeMemory: Sendable {
    public struct Entry: Sendable, Hashable {
        public var view: CalendarPeriod
        public var anchor: CalendarDate
    }

    private struct State {
        var entries: [String: Entry] = [:]
        var order: [String] = []
    }

    public static let shared = EventRangeMemory()

    let capacity: Int
    private let state = LockedValue(State())

    public init(capacity: Int = 500) {
        self.capacity = max(1, capacity)
    }

    public func remember(_ eventIds: [String], view: CalendarPeriod, anchor: CalendarDate) {
        guard !eventIds.isEmpty else { return }
        let entry = Entry(view: view, anchor: anchor)
        state.update { state in
            let incoming = Set(eventIds)
            state.order.removeAll { incoming.contains($0) }
            var added = Set<String>()
            for id in eventIds where added.insert(id).inserted {
                state.entries[id] = entry
                state.order.append(id)
            }
            while state.order.count > capacity {
                let evicted = state.order.removeFirst()
                state.entries[evicted] = nil
            }
        }
    }

    public func entry(for eventId: String) -> Entry? {
        state.get().entries[eventId]
    }

    var count: Int { state.get().entries.count }
}
