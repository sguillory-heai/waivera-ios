#if canImport(UIKit)
    import SwiftUI

    /// SwiftUI animations for the motion tokens. Always pass the view's `accessibilityReduceMotion`.
    public enum Motion {
        /// `nil` means "no animation" (Reduce Motion on a press) or "leave it to the system" (navigate).
        public static func animation(_ token: MotionToken, reduceMotion: Bool) -> Animation? {
            switch MotionPolicy.curve(for: token, reduceMotion: reduceMotion) {
            case .snappy(let duration):
                Animation.snappy(duration: duration)
            case .smooth(let duration):
                Animation.smooth(duration: duration)
            case .bouncy(let duration, let extraBounce):
                Animation.bouncy(duration: duration, extraBounce: extraBounce)
            case .crossFade(let duration):
                Animation.easeInOut(duration: duration)
            case .system, .none:
                nil
            }
        }

        /// Transition for views entering or leaving: a move plus fade, or a plain fade under Reduce Motion.
        public static func transition(edge: Edge, reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
        }
    }

    public extension View {
        /// Animates changes to `value` with a motion token, honouring Reduce Motion.
        func waiveraAnimation(_ token: MotionToken, value: some Equatable) -> some View {
            modifier(TokenAnimation(token: token, value: value))
        }
    }

    private struct TokenAnimation<Value: Equatable>: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let token: MotionToken
        let value: Value

        func body(content: Content) -> some View {
            content.animation(Motion.animation(token, reduceMotion: reduceMotion), value: value)
        }
    }
#endif
