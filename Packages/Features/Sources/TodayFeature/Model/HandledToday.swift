import Foundation
import WaiveraAPI
import WaiveraData

/// How many Needs you items the person has handled today, tallied on this device. The API has
/// no such count, so Today watches the open items and counts each one that leaves: a chat read,
/// a mention marked read, a message that finally went out, an invitation answered.
///
/// `day` is a date in the employee's saved zone (never the device's or UTC), so the tally resets
/// at the employee's local midnight, also on 23- and 25-hour days. Keys are opaque item ids,
/// never names or message text.
struct HandledTally: Codable, Hashable, Sendable {
    var userId: String
    /// `CalendarDate.isoString` of the day the tally is for.
    var day: String
    var handled: Int
    /// The keys that needed the person when last seen.
    var open: Set<String>
    /// The keys in `open` whose handling can be taken back (invitations).
    var openUndoable: Set<String> = []
    /// Handled keys whose return means the handling was undone, not a new item.
    var undoable: Set<String> = []

    var total: Int { handled + open.count }
}

/// What needs the person right now. Only built when every source behind the list has loaded and
/// none failed: a list missing a source would read as everything in it being handled.
struct HandledObservation: Hashable, Sendable {
    var userId: String
    var day: CalendarDate
    var open: Set<String>
    /// The keys in `open` whose return after leaving undoes their handling (invitations).
    var undoable: Set<String> = []
}

enum HandledToday {
    /// The tally after `observation`. A new day or a different person starts from zero with
    /// today's open items. Otherwise each key that left the open set counts once, and an undoable
    /// key that comes back takes its count off again. A key that returns for a new reason (a new
    /// message in a chat read earlier) is simply open again, and counts again when handled.
    static func advance(_ previous: HandledTally?, _ observation: HandledObservation) -> HandledTally {
        let day = observation.day.isoString
        guard let previous, previous.userId == observation.userId, previous.day == day else {
            return HandledTally(
                userId: observation.userId,
                day: day,
                handled: 0,
                open: observation.open,
                openUndoable: observation.undoable
            )
        }
        let resolved = previous.open.subtracting(observation.open)
        let returned = observation.open.subtracting(previous.open).intersection(previous.undoable)
        return HandledTally(
            userId: observation.userId,
            day: day,
            handled: max(0, previous.handled + resolved.count - returned.count),
            open: observation.open,
            openUndoable: observation.undoable,
            undoable: previous.undoable.subtracting(returned).union(resolved.intersection(previous.openUndoable))
        )
    }
}

/// How Today feeds the tally and reads the hero's ring back from it.
enum HandledRules {
    /// What needs the person, for the tally: only when Needs you, the schedule (invitations) and
    /// the activity feed (mentions) have all loaded without failing (`complete`). Every open item
    /// counts, including those folded out of view.
    static func observation(
        userId: String?,
        today: CalendarDate,
        openItems: [NeedsYouItem],
        complete: Bool
    ) -> HandledObservation? {
        guard let userId, complete else { return nil }
        let keys = Set(openItems.map(\.id))
        let invitations = Set(
            openItems.compactMap { item -> String? in
                if case .invitation = item { return item.id }
                return nil
            }
        )
        return HandledObservation(userId: userId, day: today, open: keys, undoable: invitations)
    }

    /// The ring as it will be once `observation` is saved, worked out here so it never flickers a
    /// step behind. Without a complete observation it keeps today's saved count, if any.
    static func progress(
        saved: HandledTally?,
        userId: String?,
        today: CalendarDate,
        needsYou: NeedsYouSection,
        observation: HandledObservation?
    ) -> TodayProgress? {
        if let observation {
            let tally = HandledToday.advance(saved, observation)
            return TodayProgress(handled: tally.handled, open: tally.open.count)
        }
        guard needsYou.isReady else { return nil }
        let current = saved.flatMap { $0.userId == userId && $0.day == today.isoString ? $0 : nil }
        return TodayProgress(handled: current?.handled ?? 0, open: needsYou.totalCount)
    }
}

/// Where the tally is kept between launches: one small JSON value in device-local storage.
protocol HandledTallyStore: Sendable {
    func load() -> HandledTally?
    func save(_ tally: HandledTally)
}

/// The tally in a `KeyValueStore`. A value an older build wrote in another shape reads as no
/// tally yet, never as a crash. Another person signing in starts from zero (the tally names its
/// user), so it is safe to leave across sign-out.
struct KeyValueHandledTallyStore: HandledTallyStore {
    static let key = "waivera.today.handled"
    let store: any KeyValueStore

    func load() -> HandledTally? { store.value(HandledTally.self, forKey: Self.key) }
    func save(_ tally: HandledTally) { store.setValue(tally, forKey: Self.key) }
}
