#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One fact on the event card (Android `DetailRow`): a teal tile, the value, then up to two
    /// quieter lines (the date, the time zone note). Read as one element.
    struct EventDetailRow: View {
        let systemImage: String
        /// Spoken before the value when the glyph carries meaning (online or in person).
        let iconLabel: String?
        let primary: String
        var secondary: String?
        var tertiary: String?
        var trailingSystemImage: String?

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                IconTile(
                    systemImage: systemImage,
                    tone: .teal,
                    size: ControlSize.cardTile,
                    glyphSize: ControlSize.cardTileGlyph
                )
                .accessibilityLabel(Text(iconLabel ?? ""))
                .accessibilityHidden(iconLabel == nil)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(primary)
                        .waiveraTextStyle(.titleSmall)
                        .foregroundStyle(Palette.text)
                    if let secondary {
                        Text(secondary)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if let tertiary {
                        Text(tertiary)
                            .waiveraTextStyle(.labelMedium)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let trailingSystemImage {
                    Image(systemName: trailingSystemImage)
                        .font(.system(size: ControlSize.iconSmall))
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: ControlSize.icon, height: ControlSize.icon)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
