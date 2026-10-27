#if canImport(UIKit)
    import SwiftUI

    /// A settings switch row with the toggle haptic. Rows stay readable when disabled.
    public struct ToggleRow: View {
        private let title: String
        private let subtitle: String?
        @Binding private var isOn: Bool

        public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) {
            self.title = title
            self.subtitle = subtitle
            _isOn = isOn
        }

        public var body: some View {
            Toggle(isOn: $isOn) {
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(title)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.text)
                    if let subtitle {
                        Text(subtitle)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .tint(Palette.accent)
            .padding(.vertical, Spacing.small)
            .padding(.horizontal, Spacing.medium)
            .frame(minHeight: ControlSize.minHitTarget)
            .waiveraHaptic(.toggle, trigger: isOn)
        }
    }

    private struct ToggleGallery: View {
        @State private var push = true
        @State private var previews = false

        var body: some View {
            VStack(spacing: 0) {
                ToggleRow("Push notifications", isOn: $push)
                ToggleRow(
                    "Show message previews",
                    subtitle: "When off, notification text can be reduced to a generic alert.",
                    isOn: $previews
                )
                .disabled(true)
            }
            .background(Palette.surface)
        }
    }

    #Preview("Light") { ToggleGallery() }
    #Preview("Dark") { ToggleGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { ToggleGallery().dynamicTypeSize(.accessibility5) }
#endif
