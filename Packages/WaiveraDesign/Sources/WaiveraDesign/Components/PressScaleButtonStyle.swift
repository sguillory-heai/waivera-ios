#if canImport(UIKit)
    import SwiftUI

    /// The single press primitive: springs to 0.96 with the `press` token, or dims instead of
    /// scaling under Reduce Motion. No haptic on a plain press (UX research feedback map).
    public struct PressScaleButtonStyle: ButtonStyle {
        public init() {}

        public func makeBody(configuration: Configuration) -> some View {
            PressScaleBody(configuration: configuration)
        }
    }

    private struct PressScaleBody: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let configuration: ButtonStyleConfiguration

        var body: some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? MotionPolicy.pressedScale(reduceMotion: reduceMotion) : 1)
                .opacity(configuration.isPressed && reduceMotion ? Emphasis.pressed : 1)
                .animation(Motion.animation(.press, reduceMotion: reduceMotion), value: configuration.isPressed)
        }
    }

    public extension ButtonStyle where Self == PressScaleButtonStyle {
        static var pressScale: PressScaleButtonStyle { PressScaleButtonStyle() }
    }

    #Preview("Light") {
        Button("Press me") {}
            .buttonStyle(.pressScale)
            .padding(Spacing.large)
    }

    #Preview("Dark") {
        Button("Press me") {}
            .buttonStyle(.pressScale)
            .padding(Spacing.large)
            .preferredColorScheme(.dark)
    }

    #Preview("AX XXXL") {
        Button("Press me") {}
            .buttonStyle(.pressScale)
            .padding(Spacing.large)
            .dynamicTypeSize(.accessibility5)
    }
#endif
