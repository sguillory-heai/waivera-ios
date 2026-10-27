import Foundation
import WaiveraAPI

/// Which chat surfaces are on screen and whether the app is in the foreground. Shared by
/// unread counting, in-app alerts and foreground push suppression.
///
/// A conversation's timeline and a thread are separate surfaces (IF-02): while only a thread
/// is showing, the conversation's main timeline is not visible, so its new messages count as
/// unread and alert as usual, and the other way round.
public final class ChatPresence: Sendable {
    private struct State {
        var conversations: [Int: Int] = [:]
        var threads: [Int: Int] = [:]
        var isForeground = true
    }

    private let state = LockedValue(State())

    public init() {}

    /// The conversation's main timeline appeared or disappeared. Reference counted, so two
    /// copies of the same screen keep it visible until both are gone.
    public func setVisible(_ conversationId: Int, _ visible: Bool) {
        state.update { Self.count(&$0.conversations, conversationId, visible) }
    }

    /// A thread (by its root message) appeared or disappeared. Reference counted.
    public func setThreadVisible(_ rootMessageId: Int, _ visible: Bool) {
        state.update { Self.count(&$0.threads, rootMessageId, visible) }
    }

    public func setForeground(_ isForeground: Bool) {
        state.update { $0.isForeground = isForeground }
    }

    public var isForeground: Bool { state.get().isForeground }

    /// The conversation's main timeline is on screen and the app is active (05 §5 `isActive`).
    public func isActive(_ conversationId: Int) -> Bool {
        let current = state.get()
        return current.isForeground && current.conversations[conversationId] != nil
    }

    /// The thread is on screen and the app is active.
    public func isThreadActive(_ rootMessageId: Int) -> Bool {
        let current = state.get()
        return current.isForeground && current.threads[rootMessageId] != nil
    }

    /// Where a message would be seen: a root message in its conversation's timeline, a thread
    /// reply in its thread.
    public func isActive(conversationId: Int, threadRootMessageId: Int?) -> Bool {
        if let threadRootMessageId { return isThreadActive(threadRootMessageId) }
        return isActive(conversationId)
    }

    /// Conversations whose main timeline is on screen, foreground or not.
    public var visibleConversationIds: Set<Int> { Set(state.get().conversations.keys) }

    public func reset() {
        state.update { state in
            state.conversations.removeAll()
            state.threads.removeAll()
        }
    }

    private static func count(_ counts: inout [Int: Int], _ id: Int, _ visible: Bool) {
        let count = counts[id, default: 0] + (visible ? 1 : -1)
        counts[id] = count > 0 ? count : nil
    }
}
