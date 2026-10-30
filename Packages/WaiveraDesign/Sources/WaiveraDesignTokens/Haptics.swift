/// The only moments in the whole app that vibrate (the owner's haptics policy, 2026-10-29: "avoid
/// vibrations where possible"). Everything else is silent and motion carries the feedback: taps,
/// long presses, toggles, selection, swipe thresholds, successes (copy, save, accept, bookmark, a
/// message that sends), warnings (destructive confirms, going offline), incoming messages, and
/// every other error or failed validation. A new vibration needs a new case here and a policy
/// change from the owner, never a call site.
public enum HapticMoment: String, CaseIterable, Sendable {
    /// A message or reply failed to send. Once per failure, never for a send that works.
    case sendFailed
    /// Sign-in credentials were rejected; the form shakes with it. Never for a network failure.
    case signInRejected
}

/// The one system signal a moment plays. Mirrors SwiftUI `SensoryFeedback` without importing it.
public enum HapticPattern: Equatable, Sendable {
    /// `SensoryFeedback.error` / `UINotificationFeedbackGenerator` `.error`: Android's `Reject`.
    case error
}

public enum HapticMap {
    public static func pattern(for moment: HapticMoment) -> HapticPattern {
        switch moment {
        case .sendFailed, .signInRejected: .error
        }
    }
}

/// Decides whether a haptic actually plays: honours the Settings switch and drops a repeat of the
/// same moment inside `minimumRepeatInterval`, so a burst of failures does not stack into a buzz.
public struct HapticGate: Sendable {
    /// Android's `MIN_REPEAT_MILLIS`.
    public static let minimumRepeatInterval = 0.150

    public var isEnabled: Bool
    private var lastMoment: HapticMoment?
    private var lastPlayed: Double?

    public init(isEnabled: Bool = true) {
        self.isEnabled = isEnabled
    }

    /// Returns the pattern to play now, or `nil`. `now` is seconds on a monotonic clock.
    public mutating func pattern(for moment: HapticMoment, now: Double) -> HapticPattern? {
        guard isEnabled else { return nil }
        if moment == lastMoment, let lastPlayed, now - lastPlayed < Self.minimumRepeatInterval {
            return nil
        }
        lastMoment = moment
        lastPlayed = now
        return HapticMap.pattern(for: moment)
    }
}
