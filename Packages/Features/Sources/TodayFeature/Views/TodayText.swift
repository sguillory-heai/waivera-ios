#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraDesign

    /// Text holding a name: up to `lines` lines, wrapping only between words. When one word is
    /// wider than the line it keeps to one line and ends in "…" rather than breaking mid-word
    /// (wave 29 N2). VoiceOver always reads the whole text.
    struct WordSafeText: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let text: String
        let style: TextStyleToken
        let lines: Int
        var alignment: TextAlignment = .leading
        @State private var width: CGFloat = 0

        var body: some View {
            let wraps = WordFit.wraps(widestWord: Double(widestWord), lineWidth: Double(width))
            Text(text)
                .waiveraTextStyle(style)
                .multilineTextAlignment(alignment)
                .lineLimit(wraps ? max(1, lines) : 1)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: frameAlignment)
                .readWidth { width = $0 }
                .accessibilityLabel(Text(text))
        }

        private var frameAlignment: Alignment {
            switch alignment {
            case .center: .center
            case .trailing: .trailing
            default: .leading
            }
        }

        private var widestWord: CGFloat {
            TodayMeasure.widestWord(in: text, style: style, size: dynamicTypeSize)
        }
    }

    /// Measures set text with the style's font at the current Dynamic Type size.
    enum TodayMeasure {
        static func widestWord(in text: String, style: TextStyleToken, size: DynamicTypeSize) -> CGFloat {
            let traits = UITraitCollection(preferredContentSizeCategory: size.uiContentSizeCategory)
            let font = style.uiFont(compatibleWith: traits)
            let tracking = CGFloat(style.spec.tracking)
            return WordFit.words(text).map { word in
                let measured = (word as NSString).size(withAttributes: [.font: font]).width
                return ceil(measured + tracking * CGFloat(max(0, word.count - 1)))
            }.max() ?? 0
        }
    }

    extension DynamicTypeSize {
        var uiContentSizeCategory: UIContentSizeCategory {
            switch self {
            case .xSmall: .extraSmall
            case .small: .small
            case .medium: .medium
            case .large: .large
            case .xLarge: .extraLarge
            case .xxLarge: .extraExtraLarge
            case .xxxLarge: .extraExtraExtraLarge
            case .accessibility1: .accessibilityMedium
            case .accessibility2: .accessibilityLarge
            case .accessibility3: .accessibilityExtraLarge
            case .accessibility4: .accessibilityExtraExtraLarge
            case .accessibility5: .accessibilityExtraExtraExtraLarge
            @unknown default: .large
            }
        }
    }

    extension View {
        /// Reports the width this view is laid out at, for rules decided on measured sizes.
        func readWidth(_ onChange: @escaping (CGFloat) -> Void) -> some View {
            onGeometryChange(for: CGFloat.self, of: { $0.size.width }, action: onChange)
        }
    }
#endif
