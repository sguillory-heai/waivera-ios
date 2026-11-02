#if canImport(UIKit)
    import SwiftUI

    /// The switch as Android draws it (Material 3 with Waivera colours), so both apps show the
    /// same control: a 52×32 track; on, a violet track with a large white knob; off, a muted
    /// track with a strong outline and a small knob. iOS 26's own switch is wider and flatter.
    /// It only draws: the row around it takes the tap and speaks the state.
    public struct WaiveraSwitch: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        private let isOn: Bool
        private let isEnabled: Bool

        public init(isOn: Bool, isEnabled: Bool = true) {
            self.isOn = isOn
            self.isEnabled = isEnabled
        }

        public var body: some View {
            let knob = isOn ? SwitchMetrics.knobOn : SwitchMetrics.knobOff
            let travel = (SwitchMetrics.width - SwitchMetrics.height) / 2
            ZStack {
                Capsule()
                    .fill(trackColor)
                Capsule()
                    .strokeBorder(isOn ? Color.clear : outlineColor, lineWidth: SwitchMetrics.outline)
                Circle()
                    .fill(knobColor)
                    .frame(width: knob, height: knob)
                    .offset(x: isOn ? travel : -travel)
            }
            .frame(width: SwitchMetrics.width, height: SwitchMetrics.height)
            .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: isOn)
            .accessibilityHidden(true)
        }

        private var trackColor: Color {
            switch (isOn, isEnabled) {
            case (true, true): Palette.accentFill
            case (true, false): Palette.accent.opacity(SwitchMetrics.disabledCheckedTrackAlpha)
            case (false, _): Palette.surfaceMuted
            }
        }

        private var knobColor: Color {
            switch (isOn, isEnabled) {
            case (true, true): Palette.onAccent
            case (true, false): Palette.surface
            case (false, true): Palette.borderStrong
            case (false, false): Palette.textSecondary
            }
        }

        private var outlineColor: Color { isEnabled ? Palette.borderStrong : Palette.textSecondary }
    }

    /// Material 3 switch sizes, in points (Android dp).
    enum SwitchMetrics {
        static let width: CGFloat = 52
        static let height: CGFloat = 32
        static let knobOn: CGFloat = 24
        static let knobOff: CGFloat = 16
        static let outline: CGFloat = 2
        static let disabledCheckedTrackAlpha = 0.38
    }

    /// A `Toggle` drawn with `WaiveraSwitch`: the whole control flips it, and VoiceOver keeps the
    /// system toggle's label and state.
    public struct WaiveraToggleStyle: ToggleStyle {
        @Environment(\.isEnabled) private var isEnabled

        public init() {}

        public func makeBody(configuration: Configuration) -> some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                HStack(spacing: Spacing.mediumSmall) {
                    configuration.label
                        .frame(maxWidth: .infinity, alignment: .leading)
                    WaiveraSwitch(isOn: configuration.isOn, isEnabled: isEnabled)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
            .accessibilityRepresentation {
                Toggle(isOn: configuration.$isOn) { configuration.label }
            }
        }
    }

    public extension ToggleStyle where Self == WaiveraToggleStyle {
        static var waivera: WaiveraToggleStyle { WaiveraToggleStyle() }
    }

    private struct SwitchGallery: View {
        @State private var push = true

        var body: some View {
            VStack(spacing: Spacing.medium) {
                Toggle("Push notifications", isOn: $push).toggleStyle(.waivera)
                WaiveraSwitch(isOn: true)
                WaiveraSwitch(isOn: false)
                WaiveraSwitch(isOn: true, isEnabled: false)
                WaiveraSwitch(isOn: false, isEnabled: false)
            }
            .padding(Spacing.medium)
            .background(Palette.surface)
        }
    }

    #Preview("Light") { SwitchGallery() }
    #Preview("Dark") { SwitchGallery().preferredColorScheme(.dark) }
#endif
