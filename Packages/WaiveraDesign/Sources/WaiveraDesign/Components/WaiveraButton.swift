#if canImport(UIKit)
    import SwiftUI

    /// The button styles (Android `WaiveraButtonVariant`, v5 decision 2 option C).
    public enum WaiveraButtonVariant: Sendable {
        /// The solid violet action: a white top edge, a soft sheen and a violet glow.
        case primary
        /// The raised white button: surface fill, hairline border and a faint lift.
        case secondary
        /// A quiet filled action (lilac fill), such as joining a call from a banner.
        case tonal
        /// `tonal` drawn on the celebration wash, where the plain lilac would vanish.
        case tonalOnWash
        /// The primary's construction on the danger fill.
        case destructive
        /// A destructive action that should not shout: surface with a danger outline and ink.
        case destructiveOutline
        /// A text-only action in the accent colour.
        case text
        /// A chosen answer (lilac fill, accent outline) and the answers not chosen.
        case selected
        case unselected

        /// Kept for existing call sites: same as `text`.
        public static let plain = WaiveraButtonVariant.text

        var finish: Finish {
            switch self {
            case .primary: .glow
            case .destructive: .sheen
            case .secondary: .raised
            default: .flat
            }
        }

        enum Finish { case flat, sheen, glow, raised }
    }

    /// How big a button is (Android `WaiveraButtonSize`).
    public enum WaiveraButtonSize: Sendable {
        /// 48pt tall.
        case regular
        /// The screen's one big action (Sign in): 56pt, full width, CTA corners.
        case large
        /// 48pt with tighter side padding and a smaller icon, for buttons side by side.
        case compact
    }

    /// The shared button. While `isLoading` the label fades out and a spinner with
    /// `loadingTitle` fades in, in the same size, and taps are ignored (never a blocking overlay).
    public struct WaiveraButton: View {
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private let title: String
        private let variant: WaiveraButtonVariant
        private let size: WaiveraButtonSize
        private let systemImage: String?
        private let isLoading: Bool
        private let loadingTitle: String?
        private let fillsWidth: Bool
        private let action: () -> Void

        public init(
            _ title: String,
            variant: WaiveraButtonVariant = .primary,
            size: WaiveraButtonSize = .regular,
            systemImage: String? = nil,
            isLoading: Bool = false,
            loadingTitle: String? = nil,
            fillsWidth: Bool? = nil,
            action: @escaping () -> Void
        ) {
            self.title = title
            self.variant = variant
            self.size = size
            self.systemImage = systemImage
            self.isLoading = isLoading
            self.loadingTitle = loadingTitle
            self.fillsWidth = fillsWidth ?? (variant != .text && size != .compact)
            self.action = action
        }

        public var body: some View {
            Button {
                if !isLoading { action() }
            } label: {
                ZStack {
                    label
                        .opacity(isLoading ? 0 : 1)
                    if isLoading {
                        progress
                            .transition(.opacity)
                    }
                }
                .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: isLoading)
                .waiveraTextStyle(.labelLarge)
                .fontWeight(variant == .unselected ? .regular : nil)
                .foregroundStyle(foreground)
                .multilineTextAlignment(.center)
                .padding(.horizontal, size == .compact ? Spacing.mediumSmall : Spacing.mediumPlus)
                .padding(.vertical, Spacing.mediumSmall)
                .frame(
                    maxWidth: fillsWidth ? .infinity : nil,
                    minHeight: size == .large ? ControlSize.ctaHeight : ControlSize.buttonHeight
                )
                .background { fill }
                .overlay { sheen }
                .overlay { border }
                .contentShape(shape)
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel(Text(title))
            .accessibilityValue(isLoading ? Text(loadingTitle ?? DesignStrings.loading) : Text(verbatim: ""))
        }

        @ViewBuilder private var label: some View {
            if let systemImage {
                HStack(spacing: size == .compact ? Spacing.extraSmall : Spacing.small) {
                    Image(systemName: systemImage)
                        .imageScale(size == .compact ? .small : .medium)
                        .accessibilityHidden(true)
                    Text(title)
                }
            } else {
                Text(title)
            }
        }

        /// At large text the label alone says what is happening; a spinner beside a wrapped label
        /// sat stranded at the edge (Android UI5-10).
        private var progress: some View {
            HStack(spacing: Spacing.small) {
                if !dynamicTypeSize.isLargeText {
                    BusyIndicator(color: foreground, size: ControlSize.iconSmall)
                }
                Text(loadingTitle ?? title)
            }
            .accessibilityHidden(true)
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: size == .large ? Radius.cta : Radius.button, style: .continuous)
        }

        private var fill: some View {
            shape
                .fill(container)
                .shadow(color: liftColor, radius: liftRadius, x: 0, y: liftRadius / 2)
        }

        /// The filled button's light: a 1pt white edge along the top and a sheen that fades out by
        /// 52% of the height, over the label too (white over white stays white).
        @ViewBuilder private var sheen: some View {
            if isEnabled, variant.finish == .sheen || variant.finish == .glow {
                GeometryReader { proxy in
                    let height = max(proxy.size.height, 1)
                    let sheenEnd = CGFloat(BrandPalette.buttonSheenEnd)
                    let edgeEnd = min(Spacing.hairline / height, sheenEnd)
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: Palette.buttonEdge, location: 0),
                                .init(color: Palette.buttonEdge, location: edgeEnd),
                                .init(color: Palette.buttonSheen, location: edgeEnd),
                                .init(color: Palette.buttonSheen.opacity(0), location: sheenEnd),
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
        }

        @ViewBuilder private var border: some View {
            if let borderColor {
                shape.strokeBorder(
                    borderColor,
                    lineWidth: variant == .selected && isEnabled ? ControlSize.selectedOutline : Spacing.hairline
                )
            }
        }

        private var borderColor: Color? {
            switch variant {
            case .text: nil
            case _ where !isEnabled: Palette.border
            case .secondary, .unselected: Palette.border
            case .destructiveOutline: Palette.danger
            case .selected: Palette.accent
            default: nil
            }
        }

        private var liftColor: Color {
            guard isEnabled else { return .clear }
            switch variant.finish {
            case .glow: return Palette.buttonGlow
            case .raised: return Palette.buttonRaise
            case .flat, .sheen: return .clear
            }
        }

        private var liftRadius: CGFloat {
            switch variant.finish {
            case .glow: Elevation.buttonGlow
            case .raised: Elevation.buttonRaise
            case .flat, .sheen: 0
            }
        }

        private var foreground: Color {
            guard isEnabled else { return Palette.textSecondary }
            switch variant {
            case .primary: return Palette.onAccent
            case .destructive: return Palette.onDangerFill
            case .secondary, .unselected: return Palette.text
            case .tonal, .tonalOnWash, .selected: return Palette.onAccentSoft
            case .destructiveOutline: return Palette.dangerText
            case .text: return Palette.accent
            }
        }

        private var container: Color {
            switch variant {
            case .text: return .clear
            case .unselected: return Palette.surface
            default: break
            }
            guard isEnabled else { return Palette.surfaceMuted }
            switch variant {
            case .primary: return Palette.accentFill
            case .secondary, .destructiveOutline: return Palette.surface
            case .tonal, .selected: return Palette.accentSoft
            case .tonalOnWash: return Palette.tonalOnWash
            case .destructive: return Palette.dangerFill
            case .text, .unselected: return .clear
            }
        }
    }

    private struct WaiveraButtonGallery: View {
        var body: some View {
            ScrollView {
                VStack(spacing: Spacing.mediumSmall) {
                    WaiveraButton("Sign in", size: .large) {}
                    WaiveraButton("Send invite") {}
                    WaiveraButton("Not now", variant: .secondary) {}
                    WaiveraButton("Join on web", variant: .tonal) {}
                    WaiveraButton("Delete message", variant: .destructive) {}
                    WaiveraButton(
                        "Sign out",
                        variant: .destructiveOutline,
                        systemImage: "rectangle.portrait.and.arrow.right"
                    ) {}
                    WaiveraButton("Learn more", variant: .text) {}
                    HStack(spacing: Spacing.small) {
                        WaiveraButton("Going", variant: .selected, size: .compact, systemImage: "checkmark") {}
                        WaiveraButton("Maybe", variant: .unselected, size: .compact) {}
                    }
                    WaiveraButton("Save", isLoading: true, loadingTitle: "Saving…") {}
                    WaiveraButton("Disabled") {}.disabled(true)
                }
                .padding(Spacing.medium)
            }
            .background(Palette.background)
        }
    }

    #Preview("Light") { WaiveraButtonGallery() }
    #Preview("Dark") { WaiveraButtonGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { WaiveraButtonGallery().dynamicTypeSize(.accessibility5) }
#endif
