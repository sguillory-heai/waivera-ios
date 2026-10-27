#if canImport(UIKit)
    import SwiftUI
    import UIKit

    public extension HapticPattern {
        var sensoryFeedback: SensoryFeedback {
            switch self {
            case .selection: .selection
            case .impactLight: .impact(weight: .light)
            case .impactMedium: .impact(weight: .medium)
            case .success: .success
            case .warning: .warning
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
        /// Plays the haptic mapped to `event` whenever `trigger` changes, if haptics are on.
        func waiveraHaptic<T: Equatable>(_ event: HapticEvent, trigger: T) -> some View {
            modifier(HapticModifier(event: event, trigger: trigger, condition: nil))
        }

        /// Plays the haptic only when `condition(old, new)` holds, e.g. when a state becomes `.failed`.
        func waiveraHaptic<T: Equatable>(
            _ event: HapticEvent,
            trigger: T,
            condition: @escaping @Sendable (T, T) -> Bool
        ) -> some View {
            modifier(HapticModifier(event: event, trigger: trigger, condition: condition))
        }
    }

    private struct HapticModifier<T: Equatable>: ViewModifier {
        @Environment(\.waiveraHapticsEnabled) private var isEnabled
        let event: HapticEvent
        let trigger: T
        /// `@Sendable` because `sensoryFeedback` may call its closure off the main actor.
        let condition: (@Sendable (T, T) -> Bool)?

        func body(content: Content) -> some View {
            let enabled = isEnabled
            let event = event
            let condition = condition
            return content.sensoryFeedback(trigger: trigger) { old, new in
                guard enabled, condition?(old, new) ?? true else { return nil }
                return HapticMap.pattern(for: event)?.sensoryFeedback
            }
        }
    }

    /// Imperative haptics for moments that are not tied to a view value change (a sheet button
    /// that dismisses its own view, a model event). Shares the burst gate and the Settings switch.
    @MainActor
    public final class HapticPlayer {
        public static let shared = HapticPlayer()

        private var gate = HapticGate()

        public init() {}

        public var isEnabled: Bool {
            get { gate.isEnabled }
            set { gate.isEnabled = newValue }
        }

        public func play(_ event: HapticEvent) {
            guard let pattern = gate.pattern(for: event, now: ProcessInfo.processInfo.systemUptime) else { return }
            switch pattern {
            case .selection:
                UISelectionFeedbackGenerator().selectionChanged()
            case .impactLight:
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            case .impactMedium:
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            case .success:
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .warning:
                UINotificationFeedbackGenerator().notificationOccurred(.warning)
            case .error:
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
        }
    }
#endif
