#if canImport(UIKit)
    import SwiftUI

    /// SwiftUI animations for the motion specs. Always pass the view's `accessibilityReduceMotion`.
    ///
    /// A Compose `spring(dampingRatio, stiffness)` is SwiftUI's
    /// `spring(response: 2π / √stiffness, dampingFraction: dampingRatio)` (unit mass), so every
    /// spring here settles and overshoots exactly as on Android. Tweens keep Android's cubic curves.
    public enum Motion {
        /// `nil` means "no animation" (Reduce Motion on a spatial move) or "leave it to the system".
        public static func animation(_ token: MotionToken, reduceMotion: Bool) -> Animation? {
            animation(MotionPolicy.curve(for: token, reduceMotion: reduceMotion))
        }

        public static func animation(_ curve: MotionCurve) -> Animation? {
            switch curve {
            case .spring(let spec): animation(spec)
            case .tween(let spec): animation(spec)
            case .none, .system: nil
            }
        }

        public static func animation(_ spec: SpringSpec) -> Animation {
            .spring(response: spec.response, dampingFraction: spec.dampingFraction, blendDuration: 0)
        }

        public static func animation(_ spec: TweenSpec) -> Animation {
            let curve = Animation.timingCurve(
                spec.easing.controlX1,
                spec.easing.controlY1,
                spec.easing.controlX2,
                spec.easing.controlY2,
                duration: spec.duration
            )
            return spec.delay > 0 ? curve.delay(spec.delay) : curve
        }

        /// Transition for views entering or leaving: a move plus fade, or a plain fade under Reduce Motion.
        public static func transition(edge: Edge, reduceMotion: Bool) -> AnyTransition {
            reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
        }

        /// A view popping in from `MotionTiming.popStartScale` on the pop spring, leaving on the
        /// quick exit; a short fade under Reduce Motion.
        public static func pop(reduceMotion: Bool) -> AnyTransition {
            if reduceMotion {
                return .opacity.animation(animation(MotionSpec.reducedFade))
            }
            let insertion = AnyTransition.scale(scale: MotionTiming.popStartScale)
                .combined(with: .opacity)
                .animation(animation(MotionSpec.pop))
            let removal = AnyTransition.opacity.animation(animation(MotionSpec.exit))
            return .asymmetric(insertion: insertion, removal: removal)
        }

        /// Content arriving after other content left (not a swap side): fades in after the exit.
        public static func enterAfterExit(reduceMotion: Bool) -> AnyTransition {
            let enter = animation(reduceMotion ? MotionSpec.reducedFade : MotionSpec.enterAfterExit)
            let exit = animation(reduceMotion ? MotionSpec.reducedFade : MotionSpec.exit)
            return .asymmetric(insertion: .opacity.animation(enter), removal: .opacity.animation(exit))
        }
    }

    public extension View {
        /// Animates changes to `value` with a motion token, honouring Reduce Motion.
        func waiveraAnimation(_ token: MotionToken, value: some Equatable) -> some View {
            modifier(TokenAnimation(token: token, value: value))
        }

        /// Shakes sideways once each time `trigger` changes (a wrong sign-in), `rejectShakeAfterPush`
        /// after the error banner's push. Nothing moves under Reduce Motion; the error state answers.
        func rejectShake(trigger: some Equatable) -> some View {
            modifier(ShakeModifier(trigger: trigger))
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

    private struct ShakeModifier<Trigger: Equatable>: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let trigger: Trigger
        @State private var runs = 0

        func body(content: Content) -> some View {
            content
                .modifier(ShakeAnimation(runs: runs))
                .onChange(of: trigger) {
                    if MotionPolicy.shakes(reduceMotion: reduceMotion) { runs += 1 }
                }
        }
    }

    /// The shake itself, kept out of the generic `ShakeModifier` so the keyframe closures (which
    /// SwiftUI runs as `@Sendable`) never capture the non-Sendable `Trigger` metatype.
    private struct ShakeAnimation: ViewModifier {
        let runs: Int

        func body(content: Content) -> some View {
            content
                .keyframeAnimator(initialValue: 0.0, trigger: runs) { view, value in
                    view.offset(x: CGFloat(value) * Spacing.shakeAmplitude)
                } keyframes: { _ in
                    // The banner's push lands first, then each step of `ShakeKeyframes` eases with
                    // fastOutSlowIn, as on Android.
                    KeyframeTrack {
                        LinearKeyframe(0.0, duration: MotionTiming.rejectShakeAfterPush)
                        LinearKeyframe(shakeStep(1).value, duration: shakeStep(1).duration, timingCurve: shakeEasing())
                        LinearKeyframe(shakeStep(2).value, duration: shakeStep(2).duration, timingCurve: shakeEasing())
                        LinearKeyframe(shakeStep(3).value, duration: shakeStep(3).duration, timingCurve: shakeEasing())
                        LinearKeyframe(shakeStep(4).value, duration: shakeStep(4).duration, timingCurve: shakeEasing())
                        LinearKeyframe(shakeStep(5).value, duration: shakeStep(5).duration, timingCurve: shakeEasing())
                    }
                }
        }
    }

    /// Android's fastOutSlowIn as a keyframe curve. Free functions, so the keyframe builder can
    /// call them from any isolation.
    private func shakeEasing() -> UnitCurve {
        .bezier(
            startControlPoint: UnitPoint(x: Easing.fastOutSlowIn.controlX1, y: Easing.fastOutSlowIn.controlY1),
            endControlPoint: UnitPoint(x: Easing.fastOutSlowIn.controlX2, y: Easing.fastOutSlowIn.controlY2)
        )
    }

    /// The `index`th keyframe of the shake: its value and how long the step into it takes.
    private func shakeStep(_ index: Int) -> (value: Double, duration: Double) {
        let frames = ShakeKeyframes.frames
        guard frames.indices.contains(index), index > 0 else { return (0, 0) }
        return (frames[index].value, frames[index].time - frames[index - 1].time)
    }

    private struct MotionGallery: View {
        @State private var shown = true
        @State private var rejections = 0

        var body: some View {
            VStack(spacing: Spacing.large) {
                Button("Toggle pop") { shown.toggle() }
                if shown {
                    Text(verbatim: "Popped")
                        .padding(Spacing.medium)
                        .background(Palette.accentSoft, in: Capsule())
                        .transition(Motion.pop(reduceMotion: false))
                }
                Button("Shake") { rejections += 1 }
                Text(verbatim: "Wrong password")
                    .foregroundStyle(Palette.dangerText)
                    .rejectShake(trigger: rejections)
            }
            .animation(Motion.animation(.state, reduceMotion: false), value: shown)
            .padding(Spacing.large)
            .background(Palette.background)
        }
    }

    #Preview("Light") { MotionGallery() }
    #Preview("Dark") { MotionGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { MotionGallery().dynamicTypeSize(.accessibility5) }
#endif
