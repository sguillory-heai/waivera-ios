import Foundation
import WaiveraRouting

/// Which delivered chat alerts a read clears (Android `cancelConversation` / `cancelThread`).
/// A conversation's main chat and each of its threads are separate: reading the chat leaves
/// thread replies, and reading a thread leaves the chat and other threads.
public enum ReadAlertMatch {
    /// `alertRoot` and `readRoot` are thread roots, nil for the main chat. An alert newer than
    /// `readAt` stays, so a late read never clears a newer message.
    public static func clears(alertRoot: Int?, alertDate: Date, readRoot: Int?, readAt: Date?) -> Bool {
        if let readAt, alertDate > readAt { return false }
        return alertRoot == readRoot
    }

    /// The thread root an alert's payload names, whether it arrived as text or a number.
    public static func threadRoot(_ userInfo: [AnyHashable: Any]) -> Int? {
        guard let value = userInfo["threadRootMessageId"] else { return nil }
        if let number = value as? Int { return number > 0 ? number : nil }
        return Identifier.positiveInt("\(value)")
    }
}
