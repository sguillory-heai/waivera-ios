/// Moments that may produce a haptic, from the UX research "Waivera feedback map".
/// Plain taps on buttons and rows have no entry on purpose: the press scale is the feedback.
public enum HapticEvent: String, CaseIterable, Sendable {
    /// A switch flips.
    case toggle
    /// Chips, segmented controls, pickers.
    case selection
    /// A swipe action crosses its threshold.
    case swipeThreshold
    /// A message leaves the device.
    case messageSent
    /// Task done, a retried send succeeded, a ticket accepted, diagnostics copied.
    case success
    /// Validation or send failure.
    case failure
    /// Destructive confirmation, going offline.
    case warning
    /// A long press opens a menu.
    case longPress
    /// Someone else's message arrives live while its conversation or thread is on screen.
    /// AGENTS.md lists "receive while visible" as a haptic moment and Android plays one (AF-13),
    /// so both platforms give the lightest tick; bursts are throttled by `HapticGate` (IF-09).
    case messageReceivedWhileVisible
}

/// The system haptic a moment plays. Mirrors SwiftUI `SensoryFeedback` without importing it.
public enum HapticPattern: Equatable, Sendable {
    case selection
    case impactLight
    case impactMedium
    case success
    case warning
    case error
}

public enum HapticMap {
    public static func pattern(for event: HapticEvent) -> HapticPattern? {
        switch event {
        case .toggle, .selection, .messageReceivedWhileVisible: .selection
        case .swipeThreshold, .messageSent: .impactLight
        case .success: .success
        case .failure: .error
        case .warning: .warning
        case .longPress: .impactMedium
        }
    }
}

/// Decides whether a haptic actually plays: honours the Settings switch and stops a burst of
/// identical events (rapid sends) from stacking into a buzz.
public struct HapticGate: Sendable {
    /// Minimum gap between two plays of the same pattern.
    public static let burstInterval = 0.25

    public var isEnabled: Bool
    private var lastPlayed: [String: Double] = [:]

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    /// Returns the pattern to play now, or `nil`. `now` is seconds on a monotonic clock.
    public mutating func pattern(for event: HapticEvent, now: Double) -> HapticPattern? {
        guard isEnabled, let pattern = HapticMap.pattern(for: event) else { return nil }
        let key = String(describing: pattern)
        if let last = lastPlayed[key], now - last < Self.burstInterval {
            return nil
        }
        lastPlayed[key] = now
        return pattern
    }
}
