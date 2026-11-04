#if canImport(UIKit)
    import ImageIO
    import PDFKit
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    struct WordBlockView: View {
        let block: WordBlock

        static func headingStyle(_ level: Int) -> TextStyleToken {
            switch level {
            case ...1: .titleLarge
            case 2: .titleMedium
            default: .titleSmall
            }
        }

        var body: some View {
            switch block.kind {
            case .heading(let level):
                Text(block.text)
                    .waiveraTextStyle(Self.headingStyle(level), weight: .bold)
                    .foregroundStyle(Palette.text)
                    .padding(.top, Spacing.small)
                    .accessibilityAddTraits(.isHeader)
            case .listItem:
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text(block.text)
                }
                .waiveraTextStyle(.bodyMedium)
                .foregroundStyle(Palette.text)
            case .paragraph:
                Text(block.text)
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.text)
            }
        }
    }
#endif
