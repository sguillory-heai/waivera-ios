#if canImport(UIKit)
    import CoreText
    import SwiftUI
    import UIKit

    /// Plus Jakarta Sans, bundled as static instances (SIL OFL 1.1, `Resources/Fonts`).
    public enum WaiveraFonts {
        /// Registers the bundled fonts for this process. Call once at app start, before the first
        /// view draws; safe to call again. Until it runs, text falls back to the system font.
        @MainActor
        public static func register() {
            guard !isRegistered else { return }
            isRegistered = true
            for weight in FontWeightToken.allCases {
                guard let url = Bundle.module.url(forResource: weight.fileName, withExtension: "ttf") else { continue }
                // A second registration of the same file fails harmlessly; nothing to report.
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }

        @MainActor private static var isRegistered = false
    }

    public extension TextStyleBase {
        var uiTextStyle: UIFont.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title1
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .subheadline: .subheadline
            case .footnote: .footnote
            case .caption: .caption1
            case .caption2: .caption2
            }
        }

        var fontTextStyle: Font.TextStyle {
            switch self {
            case .largeTitle: .largeTitle
            case .title: .title
            case .title2: .title2
            case .title3: .title3
            case .headline: .headline
            case .body: .body
            case .callout: .callout
            case .subheadline: .subheadline
            case .footnote: .footnote
            case .caption: .caption
            case .caption2: .caption2
            }
        }
    }

    public extension TextStyleToken {
        /// The style's font, scaling with Dynamic Type like the closest system text style.
        var font: Font {
            Font.custom(spec.weight.postScriptName, size: spec.size, relativeTo: base.fontTextStyle)
        }

        /// The style's font in another face (unread names), scaling like `font`.
        func font(weight: FontWeightToken?) -> Font {
            Font.custom(spec.weighted(weight).weight.postScriptName, size: spec.size, relativeTo: base.fontTextStyle)
        }

        /// The same font as a `UIFont` at the current (or given) Dynamic Type size, for measuring.
        func uiFont(compatibleWith traits: UITraitCollection? = nil) -> UIFont {
            let base =
                UIFont(name: spec.weight.postScriptName, size: spec.size)
                ?? UIFont.systemFont(ofSize: spec.size, weight: spec.weight.uiWeight)
            return UIFontMetrics(forTextStyle: self.base.uiTextStyle).scaledFont(for: base, compatibleWith: traits)
        }

        /// The style's line height scaled for Dynamic Type.
        func scaledLineHeight(compatibleWith traits: UITraitCollection? = nil) -> CGFloat {
            UIFontMetrics(forTextStyle: base.uiTextStyle).scaledValue(for: spec.lineHeight, compatibleWith: traits)
        }
    }

    public extension FontWeightToken {
        var uiWeight: UIFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            case .extraBold: .heavy
            }
        }
    }

    public extension Font {
        static func waivera(_ style: TextStyleToken) -> Font { style.font }
    }

    /// The text styles existing feature code uses by role, mapped to the Android type scale.
    public enum WaiveraFont {
        public static let screenTitle = LegacyFontRole.screenTitle.style.font
        public static let sectionTitle = LegacyFontRole.sectionTitle.style.font
        public static let body = LegacyFontRole.body.style.font
        public static let bodyEmphasis = LegacyFontRole.bodyEmphasis.style.font
        public static let subtitle = LegacyFontRole.subtitle.style.font
        public static let caption = LegacyFontRole.caption.style.font
        public static let captionEmphasis = LegacyFontRole.captionEmphasis.style.font
        public static let label = LegacyFontRole.label.style.font
        public static let eyebrow = LegacyFontRole.eyebrow.style.font
        public static let badge = LegacyFontRole.badge.style.font
        public static let button = LegacyFontRole.button.style.font
    }

    public extension View {
        /// Font, tracking and line height of a type-scale style. Prefer this over `.font` for
        /// multi-line text so line height matches Android.
        func waiveraTextStyle(_ style: TextStyleToken) -> some View {
            modifier(TextStyleModifier(style: style, weight: nil))
        }

        /// The style in another face: `.waiveraTextStyle(.titleSmall, weight: .extraBold)`. Use
        /// it instead of `.fontWeight`, which may not switch a custom font's face.
        func waiveraTextStyle(_ style: TextStyleToken, weight: FontWeightToken?) -> some View {
            modifier(TextStyleModifier(style: style, weight: weight))
        }
    }

    private struct TextStyleModifier: ViewModifier {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let style: TextStyleToken
        let weight: FontWeightToken?

        func body(content: Content) -> some View {
            let traits = UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(dynamicTypeSize))
            let font = style.uiFont(compatibleWith: traits)
            let lineSpacing = max(0, style.scaledLineHeight(compatibleWith: traits) - font.lineHeight)
            content
                .font(style.font(weight: weight))
                .tracking(style.spec.tracking)
                .lineSpacing(lineSpacing)
        }
    }

    extension UIContentSizeCategory {
        init(_ size: DynamicTypeSize) {
            switch size {
            case .xSmall: self = .extraSmall
            case .small: self = .small
            case .medium: self = .medium
            case .large: self = .large
            case .xLarge: self = .extraLarge
            case .xxLarge: self = .extraExtraLarge
            case .xxxLarge: self = .extraExtraExtraLarge
            case .accessibility1: self = .accessibilityMedium
            case .accessibility2: self = .accessibilityLarge
            case .accessibility3: self = .accessibilityExtraLarge
            case .accessibility4: self = .accessibilityExtraExtraLarge
            case .accessibility5: self = .accessibilityExtraExtraExtraLarge
            @unknown default: self = .large
            }
        }
    }

    public extension DynamicTypeSize {
        /// The plain-data category the token rules take.
        var category: TextSizeCategory {
            switch self {
            case .xSmall: .xSmall
            case .small: .small
            case .medium: .medium
            case .large: .large
            case .xLarge: .xLarge
            case .xxLarge: .xxLarge
            case .xxxLarge: .xxxLarge
            case .accessibility1: .accessibility1
            case .accessibility2: .accessibility2
            case .accessibility3: .accessibility3
            case .accessibility4: .accessibility4
            case .accessibility5: .accessibility5
            @unknown default: .large
            }
        }

        /// Above 130%: layouts take their large-text form.
        var isLargeText: Bool { TypeScale.isLarge(category) }
        /// From 150%: layouts take their largest-text form.
        var isExtraLargeText: Bool { TypeScale.isExtraLarge(category) }
    }

    public extension TextSizeCategory {
        var dynamicTypeSize: DynamicTypeSize {
            switch self {
            case .xSmall: .xSmall
            case .small: .small
            case .medium: .medium
            case .large: .large
            case .xLarge: .xLarge
            case .xxLarge: .xxLarge
            case .xxxLarge: .xxxLarge
            case .accessibility1: .accessibility1
            case .accessibility2: .accessibility2
            case .accessibility3: .accessibility3
            case .accessibility4: .accessibility4
            case .accessibility5: .accessibility5
            }
        }
    }

    private struct TypographyGallery: View {
        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.small) {
                    ForEach(TextStyleToken.allCases, id: \.self) { style in
                        Text(verbatim: style.rawValue)
                            .waiveraTextStyle(style)
                            .foregroundStyle(Palette.text)
                    }
                }
                .padding(Spacing.medium)
            }
            .background(Palette.background)
            .onAppear { WaiveraFonts.register() }
        }
    }

    #Preview("Light") { TypographyGallery() }
    #Preview("Dark") { TypographyGallery().preferredColorScheme(.dark) }
    #Preview("AX5") { TypographyGallery().dynamicTypeSize(.accessibility5) }
#endif
