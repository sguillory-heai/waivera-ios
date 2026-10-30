#if canImport(UIKit)
    import SwiftUI
    import UIKit

    // The owner's policy (2026-10-29): only a failed send and a wrong sign-in vibrate. There is no
    // API here for any other moment on purpose; see `HapticMoment`.

    public extension HapticPattern {
        var sensoryFeedback: SensoryFeedback {
            switch self {
            case .error: .error
            }
        }
    }

    private struct HapticsEnabledKey: EnvironmentKey {
        static let defaultValue = true
    }

    public extension EnvironmentValues {
        /// The Settings "Haptics" switch. The app root sets it from `SettingsRepository`.
        var waiveraHapticsEnabled: Bool {
            get { self[HapticsEnabledKey.self] }
            set { self[HapticsEnabledKey.self] = newValue }
        }
    }

    public extension View {
        /// Plays `moment`'s haptic when `condition(old, new)` holds for a change of `trigger`, for
        /// example when a send's state becomes `.failed`, if haptics are on.
        func waiveraHaptic<T: Equatable>(
            _ moment: HapticMoment,
            trigger: T,
            condition: @escaping @Sendable (T, T) -> Bool
        ) -> some View {
            modifier(HapticModifier(moment: moment, trigger: trigger, condition: condition))
        }
    }

    private struct HapticModifier<T: Equatable>: ViewModifier {
        @Environment(\.waiveraHapticsEnabled) private var isEnabled
        let moment: HapticMoment
        let trigger: T
        /// `@Sendable` because `sensoryFeedback` may call its closure off the main actor.
        let condition: @Sendable (T, T) -> Bool

        func body(content: Content) -> some View {
            let enabled = isEnabled
            let pattern = HapticMap.pattern(for: moment)
            let condition = condition
            return content.sensoryFeedback(trigger: trigger) { old, new in
                guard enabled, condition(old, new) else { return nil }
                return pattern.sensoryFeedback
            }
        }
    }

    /// Imperative haptics for the two moments when they come from a model event rather than a view
    /// value change. Shares the burst gate and the Settings switch.
    @MainActor
    public final class HapticPlayer {
        public static let shared = HapticPlayer()

        private var gate = HapticGate()

        public init() {}

        public var isEnabled: Bool {
            get { gate.isEnabled }
            set { gate.isEnabled = newValue }
        }

        public func play(_ moment: HapticMoment) {
            guard let pattern = gate.pattern(for: moment, now: ProcessInfo.processInfo.systemUptime) else { return }
            switch pattern {
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
#endif
