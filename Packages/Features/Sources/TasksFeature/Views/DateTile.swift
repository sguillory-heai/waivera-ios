#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The month and day of the due date on a soft tile; a calendar glyph without one.
    struct DateTile: View {
        let month: String?
        let day: String?
        let tone: TileTone

        var body: some View {
            Group {
                if let month, let day {
                    VStack(spacing: 0) {
                        Text(month.uppercased())
                            .waiveraTextStyle(.labelSmall, weight: .bold)
                        Text(day)
                            .waiveraTextStyle(.titleMedium, weight: .bold)
                            .monospacedDigit()
                    }
                    .foregroundStyle(tone.contentColor)
                    .frame(width: ControlSize.cardTile, height: ControlSize.cardTile)
                    .background(tone.containerColor, in: RoundedRectangle(cornerRadius: Radius.tile))
                } else {
                    IconTile(
                        systemImage: "calendar",
                        tone: .neutral,
                        size: ControlSize.cardTile,
                        glyphSize: ControlSize.cardTileGlyph
                    )
                }
            }
            .accessibilityHidden(true)
        }
    }
#endif
