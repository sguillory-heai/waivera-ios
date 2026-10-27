import Foundation
import WaiveraAPI

/// Incoming typing indicators: expire after 5 s unless refreshed, clear when that user's
/// message arrives, and clear entirely on reconnect (05 §6, PLAN parity fix).
public actor TypingTracker {
    public static let expiry: TimeInterval = 5

    private let clock: any WaiveraClock
    private var entries: [Int: [String: Date]] = [:]
    private var expiryTask: Task<Void, Never>?
    nonisolated let cell = StateCell<[Int: [String]]>([:])

    public init(clock: any WaiveraClock) {
        self.clock = clock
    }

    public func received(conversationId: Int, userId: String, isTyping: Bool) {
        if isTyping {
            entries[conversationId, default: [:]][userId] = clock.now.addingTimeInterval(Self.expiry)
        } else {
            entries[conversationId]?[userId] = nil
        }
        publish()
    }

    public func messageArrived(conversationId: Int, authorId: String?) {
        guard let authorId, entries[conversationId]?[authorId] != nil else { return }
        entries[conversationId]?[authorId] = nil
        publish()
    }

    public func clearAll() {
        entries.removeAll()
        publish()
    }

    public func prune() {
        publish()
    }

    private func publish() {
        let now = clock.now
        for (conversationId, users) in entries {
            let live = users.filter { $0.value > now }
            entries[conversationId] = live.isEmpty ? nil : live
        }
        let snapshot = entries.mapValues { $0.keys.sorted() }
        if snapshot != cell.current { cell.set(snapshot) }
        scheduleExpiry()
    }

    private func scheduleExpiry() {
        expiryTask?.cancel()
        guard let next = entries.values.flatMap(\.values).min() else { return }
        let delay = max(0, next.timeIntervalSince(clock.now))
        let clock = clock
        expiryTask = Task {
            try? await clock.sleep(for: .milliseconds(Int64(delay * 1_000) + 1))
            guard !Task.isCancelled else { return }
            self.prune()
        }
    }
}

/// Outgoing typing: `true` on the first keystroke and at most every 3 s while typing,
/// `false` after 1.8 s idle, on send and on leave (03 §11, PLAN parity fix).
public actor TypingThrottle {
    public static let interval: TimeInterval = 3
    public static let idleTimeout: TimeInterval = 1.8

    private let clock: any WaiveraClock
    private let sendTyping: @Sendable (Int, Bool) async -> Void
    private var lastSent: [Int: Date] = [:]
    private var idleTasks: [Int: Task<Void, Never>] = [:]

    public init(clock: any WaiveraClock, send: @escaping @Sendable (Int, Bool) async -> Void) {
        self.clock = clock
        sendTyping = send
    }

    public func textChanged(conversationId: Int, text: String) async {
        guard !text.trimmed.isEmpty else {
            await stop(conversationId: conversationId)
            return
        }
        let now = clock.now
        if let last = lastSent[conversationId], now.timeIntervalSince(last) < Self.interval {
            // Still typing and throttled.
        } else {
            lastSent[conversationId] = now
            await sendTyping(conversationId, true)
        }
        scheduleIdle(conversationId)
    }

    /// Send, leave, or an emptied composer.
    public func stop(conversationId: Int) async {
        idleTasks.removeValue(forKey: conversationId)?.cancel()
        guard lastSent.removeValue(forKey: conversationId) != nil else { return }
        await sendTyping(conversationId, false)
    }

    private func scheduleIdle(_ conversationId: Int) {
        idleTasks[conversationId]?.cancel()
        let clock = clock
        idleTasks[conversationId] = Task {
            try? await clock.sleep(for: .milliseconds(Int64(Self.idleTimeout * 1_000)))
            guard !Task.isCancelled else { return }
            await self.idleExpired(conversationId)
        }
    }

    private func idleExpired(_ conversationId: Int) async {
        idleTasks[conversationId] = nil
        guard lastSent.removeValue(forKey: conversationId) != nil else { return }
        await sendTyping(conversationId, false)
    }
}
