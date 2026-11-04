#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The month and day of the due date on a soft tile (Android `DateTile`); the task glyph without one.
    struct DateTile: View {
        let month: String?
        let day: String?
        let tone: TileTone

        var body: some View {
            Group {
                if let month, let day {
                    VStack(spacing: 0) {
                        Text(month.uppercased())
                            .waiveraTextStyle(.kicker)
                            .lineLimit(1)
                            .fixedSize()
                        Text(day)
                            .waiveraTextStyle(.titleLarge)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .foregroundStyle(tone.contentColor)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.extraSmall)
                    .frame(
                        minWidth: ControlSize.cardTile + Spacing.small,
                        minHeight: ControlSize.cardTile + Spacing.small
                    )
                    .background(
                        tone.containerColor,
                        in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous)
                    )
                } else {
                    IconTile(
                        systemImage: "list.bullet.clipboard",
                        tone: tone,
                        size: ControlSize.cardTile + Spacing.small,
                        glyphSize: ControlSize.cardTileGlyph
                    )
                }
            }
            .accessibilityHidden(true)
        }
    }
#endif
