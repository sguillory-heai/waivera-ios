#if canImport(UIKit)
    import SwiftUI

    /// The single press primitive (Android `pressFeedback`): the control sinks to its depth's scale
    /// on the press spring, stays down at least `MotionTiming.minVisiblePress` so a quick tap still
    /// reads, and comes back on the bouncy release spring. Rows and cards also darken a touch.
    /// Under Reduce Motion nothing scales; a tint answers the press instead. No haptic.
    public struct PressScaleButtonStyle: ButtonStyle {
        private let depth: PressDepth

        public init(depth: PressDepth = .button) {
            self.depth = depth
        }

        public func makeBody(configuration: Configuration) -> some View {
            PressScaleBody(isPressed: configuration.isPressed, depth: depth) {
                configuration.label
            }
        }
    }

    public extension ButtonStyle where Self == PressScaleButtonStyle {
        /// Buttons, chips, segments and bubbles.
        static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }

        /// A press at another depth: `.row`, `.card` or `.compact`.
        static func press(_ depth: PressDepth) -> PressScaleButtonStyle { PressScaleButtonStyle(depth: depth) }
    }

    /// Draws a press for a pressed flag that the caller tracks, holding it for the minimum press.
    struct PressScaleBody<Label: View>: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        let isPressed: Bool
        let depth: PressDepth
        @ViewBuilder let label: Label

        @State private var shownPressed = false
        @State private var pressedAt: Date?

        var body: some View {
            label
                .scaleEffect(shownPressed ? MotionPolicy.pressedScale(depth, reduceMotion: reduceMotion) : 1)
                .brightness(shownPressed ? tintBrightness : 0)
                .task(id: isPressed) { await follow(isPressed) }
        }

        /// Darkens in light, lightens in dark, by the press tint.
        private var tintBrightness: Double {
            let tint = MotionPolicy.pressedTint(depth, reduceMotion: reduceMotion)
            return colorScheme == .dark ? tint : -tint
        }

        private func follow(_ pressed: Bool) async {
            if pressed {
                pressedAt = Date()
                withAnimation(Motion.animation(.press, reduceMotion: reduceMotion)) { shownPressed = true }
                return
            }
            guard shownPressed else { return }
            let heldFor = pressedAt.map { Date().timeIntervalSince($0) } ?? MotionTiming.minVisiblePress
            let wait = MotionPolicy.releaseDelay(pressedFor: heldFor)
            if wait > 0 {
                try? await Task.sleep(for: .seconds(wait))
                guard !Task.isCancelled else { return }
            }
            withAnimation(Motion.animation(MotionPolicy.release(cancelled: false, reduceMotion: reduceMotion))) {
                shownPressed = false
            }
        }
    }

    public extension View {
        /// A tappable surface with a long press (a message bubble, a row with a menu): presses at
        /// `depth`, keeps sinking toward the long-press depth once the hold arms, and pops back
        /// when the long press fires. VoiceOver gets the tap as the default action and the long
        /// press as a named action.
        func waiveraPressable(
            depth: PressDepth = .button,
            longPressActionName: String,
            onTap: @escaping () -> Void,
            onLongPress: @escaping () -> Void
        ) -> some View {
            modifier(
                PressableModifier(
                    depth: depth,
                    longPressActionName: longPressActionName,
                    onTap: onTap,
                    onLongPress: onLongPress
                )
            )
        }
    }

    private struct PressableModifier: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.colorScheme) private var colorScheme
        let depth: PressDepth
        let longPressActionName: String
        let onTap: () -> Void
        let onLongPress: () -> Void

        @State private var scale: CGFloat = 1
        @State private var tint: Double = 0
        @State private var pressing = false

        func body(content: Content) -> some View {
            content
                .scaleEffect(scale)
                .brightness(colorScheme == .dark ? tint : -tint)
                .contentShape(Rectangle())
                .onTapGesture(perform: onTap)
                .onLongPressGesture(minimumDuration: MotionTiming.longPressDuration) {
                    fire()
                } onPressingChanged: { isPressing in
                    pressing = isPressing
                }
                .task(id: pressing) { await follow(pressing) }
                .accessibilityAddTraits(.isButton)
                .accessibilityAction(.default, onTap)
                .accessibilityAction(named: Text(longPressActionName), onLongPress)
        }

        private func follow(_ isPressing: Bool) async {
            guard isPressing else {
                release()
                return
            }
            withAnimation(Motion.animation(.press, reduceMotion: reduceMotion)) {
                scale = MotionPolicy.pressedScale(depth, reduceMotion: reduceMotion)
                tint = MotionPolicy.pressedTint(depth, reduceMotion: reduceMotion)
            }
            try? await Task.sleep(for: .seconds(MotionTiming.longPressArmDelay))
            guard !Task.isCancelled else { return }
            if reduceMotion {
                tint = Emphasis.longPressTint
            } else {
                withAnimation(Motion.animation(MotionPolicy.longPressSink())) {
                    scale = MotionPolicy.longPressScale(depth, reduceMotion: false)
                }
            }
        }

        private func fire() {
            withAnimation(Motion.animation(MotionPolicy.pop(reduceMotion: reduceMotion))) {
                scale = 1
                tint = 0
            }
            onLongPress()
        }

        private func release() {
            guard scale != 1 || tint != 0 else { return }
            withAnimation(Motion.animation(MotionPolicy.release(cancelled: false, reduceMotion: reduceMotion))) {
                scale = 1
                tint = 0
            }
        }
    }

    private struct PressGallery: View {
        @State private var longPresses = 0

        var body: some View {
            VStack(spacing: Spacing.large) {
                Button("Button depth") {}
                    .buttonStyle(.pressScale)
                Button("Row depth") {}
                    .frame(maxWidth: .infinity, minHeight: ControlSize.listRowMinHeight)
                    .background(Palette.surface)
                    .buttonStyle(.press(.row))
                Text(verbatim: "Hold me (\(longPresses))")
                    .padding(Spacing.medium)
                    .background(Palette.myBubble, in: RoundedRectangle(cornerRadius: Radius.bubble))
                    .waiveraPressable(
                        longPressActionName: "Message actions",
                        onTap: {},
                        onLongPress: { longPresses += 1 }
                    )
            }
            .padding(Spacing.large)
            .background(Palette.background)
        }
    }

    #Preview("Light") { PressGallery() }
    #Preview("Dark") { PressGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { PressGallery().dynamicTypeSize(.accessibility5) }
#endif
