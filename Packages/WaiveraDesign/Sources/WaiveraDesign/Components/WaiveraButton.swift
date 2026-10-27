#if canImport(UIKit)
    import SwiftUI

    public enum WaiveraButtonVariant: Sendable {
        case primary
        case secondary
        case destructive
        case plain
    }

    /// Full-width button with the four Waivera variants and an inline loading state that keeps
    /// the button's size (never a blocking overlay).
    public struct WaiveraButton: View {
        @Environment(\.isEnabled) private var isEnabled

        private let title: String
        private let variant: WaiveraButtonVariant
        private let systemImage: String?
        private let isLoading: Bool
        private let action: () -> Void

        public init(
            _ title: String,
            variant: WaiveraButtonVariant = .primary,
            systemImage: String? = nil,
            isLoading: Bool = false,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.variant = variant
            self.systemImage = systemImage
            self.isLoading = isLoading
            self.action = action
        }

        public var body: some View {
            Button(action: action) {
                ZStack {
                    label
                        .opacity(isLoading ? 0 : 1)
                    if isLoading {
                        ProgressView()
                            .tint(foreground)
                    }
                }
                .font(WaiveraFont.button)
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.smallPlus)
                .frame(maxWidth: variant == .plain ? nil : .infinity, minHeight: ControlSize.buttonHeight)
                .background(background, in: shape)
                .overlay {
                    if variant == .secondary {
                        shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                    }
                }
                .contentShape(shape)
            }
            .buttonStyle(.pressScale)
            .disabled(isLoading)
            .opacity(isEnabled ? 1 : Emphasis.disabled)
            .accessibilityLabel(Text(title))
            .accessibilityValue(isLoading ? Text(DesignStrings.loading) : Text(verbatim: ""))
        }

        @ViewBuilder private var label: some View {
            if let systemImage {
                Label(title, systemImage: systemImage)
            } else {
                Text(title)
            }
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Radius.button, style: .continuous)
        }

        private var foreground: Color {
            switch variant {
            case .primary: Palette.onAccent
            case .destructive: Palette.onDanger
            case .secondary, .plain: Palette.accent
            }
        }

        private var background: Color {
            switch variant {
            case .primary: Palette.accent
            case .destructive: Palette.danger
            case .secondary: Palette.surface
            case .plain: Color.clear
            }
        }
    }

    private struct WaiveraButtonGallery: View {
        var body: some View {
            VStack(spacing: Spacing.smallPlus) {
                WaiveraButton("Send invite") {}
                WaiveraButton("Not now", variant: .secondary) {}
                WaiveraButton("Sign out", variant: .destructive, systemImage: "rectangle.portrait.and.arrow.right") {}
                WaiveraButton("Learn more", variant: .plain) {}
                WaiveraButton("Saving", isLoading: true) {}
                WaiveraButton("Disabled") {}.disabled(true)
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    #Preview("Light") { WaiveraButtonGallery() }
    #Preview("Dark") { WaiveraButtonGallery().preferredColorScheme(.dark) }
    #Preview("AX XXXL") { WaiveraButtonGallery().dynamicTypeSize(.accessibility5) }
#endif
