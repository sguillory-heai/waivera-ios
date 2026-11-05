#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A labelled fact with its tile (Android `InfoRow`): the field label over its value, the tile
    /// centred on the row.
    struct FactRow<Value: View>: View {
        let systemImage: String
        let label: String
        var tone: TileTone = .brand
        /// A row that opens something shows a chevron, as Android's `InfoRow` with an onClick does.
        var showsChevron = false
        @ViewBuilder let value: () -> Value

        var body: some View {
            HStack(spacing: ControlSize.fieldTileGap) {
                IconTile(
                    systemImage: systemImage,
                    tone: tone,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(label)
                        .waiveraTextStyle(.fieldLabel)
                        .foregroundStyle(Palette.textSecondary)
                    value()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if showsChevron {
                    Image(waivera: "chevron.right")
                        .resizable()
                        .scaledToFit()
                        .frame(width: ControlSize.icon, height: ControlSize.icon)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: ControlSize.minHitTarget)
            .accessibilityElement(children: .combine)
        }
    }

    /// A fact's value in the field value style.
    struct FactValue: View {
        let text: String
        var color: Color = Palette.text

        var body: some View {
            Text(text)
                .waiveraTextStyle(.fieldValue)
                .foregroundStyle(color)
        }
    }
#endif
