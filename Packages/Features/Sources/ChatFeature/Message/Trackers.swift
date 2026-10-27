import Foundation
import WaiveraAPI
import WaiveraData

/// What changed in the outbox since the previous emission.
struct SendEvents: Equatable, Sendable {
    /// Errors of sends that failed since the last update, oldest first.
    var newFailures: [WaiveraError] = []
    var retrySucceeded = false
}

/// Watches outbox rows across emissions so the screen raises the send error banner (03 §11)
/// only for failures that happen while it is open, and plays one success haptic when a
/// retried message lands. Rows already failed when the screen opens show their inline Retry
/// without a banner.
struct SendTracker {
    private var initialized = false
    private var failed: Set<String> = []
    private var pendingIds: Set<String> = []
    private var retried: Set<String> = []

    mutating func markRetried(_ clientMessageId: String) {
        retried.insert(clientMessageId)
    }

    /// A discarded row is gone on purpose, not delivered.
    mutating func markDiscarded(_ clientMessageId: String) {
        retried.remove(clientMessageId)
    }

    mutating func update(_ pending: [OutgoingMessage]) -> SendEvents {
        var nowFailed: Set<String> = []
        var errors: [WaiveraError] = []
        for entry in pending.sorted(by: { $0.createdAt < $1.createdAt }) {
            guard case .failed(let error) = entry.state else { continue }
            nowFailed.insert(entry.clientMessageId)
            if initialized, !failed.contains(entry.clientMessageId) { errors.append(error) }
        }
        let nowPending = Set(pending.map(\.clientMessageId))
        let delivered = retried.filter { pendingIds.contains($0) && !nowPending.contains($0) }
        retried.subtract(delivered)
        retried.subtract(nowFailed.subtracting(failed))
        failed = nowFailed
        pendingIds = nowPending
        initialized = true
        return SendEvents(newFailures: errors, retrySucceeded: !delivered.isEmpty)
    }
}

/// Keys that appeared after the first emission and are not older than what was already shown,
/// so only live arrivals and fresh sends animate in (the first load and older pages stay
/// still). Keyed like rows, so an optimistic message does not animate again when its server
/// copy lands.
struct ArrivalTracker {
    struct Entry: Sendable {
        var key: String
        var createdAt: Date?
        var isPending: Bool
    }

    private var seen: Set<String>?
    private var newest: Date?

    /// Returns the keys of the rows that just arrived.
    mutating func update(_ entries: [Entry]) -> Set<String> {
        let previous = seen
        let previousNewest = newest
        seen = Set(entries.map(\.key))
        newest = entries.compactMap(\.createdAt).max() ?? previousNewest
        guard let previous else { return [] }
        // The first page arriving after an empty cache is history, except for one's own send.
        if previous.isEmpty { return Set(entries.filter(\.isPending).map(\.key)) }
        return Set(
            entries.filter { entry in
                guard !previous.contains(entry.key) else { return false }
                if entry.isPending { return true }
                guard let previousNewest, let createdAt = entry.createdAt else { return true }
                return createdAt >= previousNewest
            }
            .map(\.key)
        )
    }

    static func entries(messages: [ChatMessage], pending: [OutgoingMessage]) -> [Entry] {
        let ambiguous = TimelineBuilder.ambiguousClientIds(messages)
        return messages.map {
            Entry(key: TimelineBuilder.key(of: $0, ambiguous: ambiguous), createdAt: $0.createdAt, isPending: false)
        }
            + pending.map { Entry(key: TimelineBuilder.pendingKey($0), createdAt: $0.createdAt, isPending: true) }
    }
}
