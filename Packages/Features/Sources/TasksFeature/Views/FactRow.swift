#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct FactRow: View {
        let systemImage: String
        let label: String
        let value: String
        var isLate = false

        var body: some View {
            HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                IconTile(
                    systemImage: systemImage,
                    tone: isLate ? .danger : .brand,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(label)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                    Text(value)
                        .waiveraTextStyle(.bodyLarge, weight: .semibold)
                        .foregroundStyle(isLate ? Palette.dangerText : Palette.text)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.medium)
            .accessibilityElement(children: .combine)
        }
    }
#endif
