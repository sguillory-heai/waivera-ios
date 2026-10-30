#if canImport(UIKit)
    import SwiftUI

    /// The app's spinner (Android `WaiveraBusyIndicator`): an arc of `color` turning on a faint
    /// track. Under Reduce Motion it is a still ring, so nothing spins. Decorative; the control
    /// it sits in says what is happening. With endless motion disabled (UI tests) the arc stands
    /// still where it starts.
    public struct BusyIndicator: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.waiveraEndlessMotionDisabled) private var endlessMotionDisabled
        private let color: Color
        private let trackColor: Color
        private let size: CGFloat
        private let lineWidth: CGFloat
        @State private var turning = false

        public init(
            color: Color = Palette.accent,
            trackColor: Color? = nil,
            size: CGFloat = ControlSize.progressSmall,
            lineWidth: CGFloat = ControlSize.progressStroke
        ) {
            self.color = color
            self.trackColor = trackColor ?? color.opacity(Emphasis.busyTrack)
            self.size = size
            self.lineWidth = lineWidth
        }

        public var body: some View {
            ZStack {
                Circle()
                    .stroke(reduceMotion ? color.opacity(Emphasis.staticRing) : trackColor, lineWidth: lineWidth)
                if !reduceMotion {
                    Circle()
                        .trim(from: 0, to: 0.28)
                        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                        .rotationEffect(.degrees(turning ? 360 : 0))
                        .animation(.linear(duration: 0.9).repeatForever(autoreverses: false), value: turning)
                }
            }
            .padding(lineWidth / 2)
            .frame(width: size, height: size)
            .onAppear { turning = !endlessMotionDisabled }
            .accessibilityHidden(true)
        }
    }

    private struct BusyGallery: View {
        var body: some View {
            HStack(spacing: Spacing.large) {
                BusyIndicator()
                BusyIndicator(size: ControlSize.progressLarge, lineWidth: ControlSize.progressStrokeLarge)
                BusyIndicator(color: Palette.onAccent)
                    .padding(Spacing.small)
                    .background(Palette.accentFill, in: Capsule())
            }
            .padding(Spacing.large)
            .background(Palette.background)
        }
    }

    #Preview("Light") { BusyGallery() }
    #Preview("Dark") { BusyGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { BusyGallery().dynamicTypeSize(.accessibility5) }
#endif
