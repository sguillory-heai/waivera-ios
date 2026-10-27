import Foundation
import WaiveraAPI

/// Which conversations are on screen and whether the app is in the foreground. Shared by
/// unread counting, in-app alerts and foreground push suppression.
public final class ChatPresence: Sendable {
    private struct State {
        var visible: [Int: Int] = [:]
        var isForeground = true
    }

    private let state = LockedValue(State())

    public init() {}

    /// Reference counted: a thread over its conversation keeps the conversation visible.
    public func setVisible(_ conversationId: Int, _ visible: Bool) {
        state.update { state in
            let count = state.visible[conversationId, default: 0] + (visible ? 1 : -1)
            state.visible[conversationId] = count > 0 ? count : nil
        }
    }

    public func setForeground(_ isForeground: Bool) {
        state.update { $0.isForeground = isForeground }
    }

    public var isForeground: Bool { state.get().isForeground }

    /// On screen and the app is active (05 §5 `isActive`).
    public func isActive(_ conversationId: Int) -> Bool {
        let current = state.get()
        return current.isForeground && current.visible[conversationId] != nil
    }

    public func reset() {
        state.update { $0.visible.removeAll() }
    }
}
