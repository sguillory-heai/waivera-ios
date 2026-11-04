import Foundation

/// The keyboard's echo after a send. When the field is cleared while the keyboard still holds
/// an autocorrect or predictive suggestion, UIKit commits that suggestion back into the field a
/// moment later, so the sent text reappears in the composer. Nobody types more than one
/// character that fast, so a multi-character jump from empty right after Send is the echo.
enum ComposerEcho {
    static let window: TimeInterval = 0.6

    static func isEcho(sentAt: Date?, now: Date, old: String, new: String) -> Bool {
        guard let sentAt, now.timeIntervalSince(sentAt) < window else { return false }
        return old.isEmpty && new.count > 1
    }
}
