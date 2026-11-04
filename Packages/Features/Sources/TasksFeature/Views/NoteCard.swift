#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A tinted note above the facts: a pending request or an active delay.
    struct NoteCard: View {
        let title: String
        let message: String
        let systemImage: String
        let tone: TileTone

        var body: some View {
            HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                IconTile(
                    systemImage: systemImage,
                    tone: tone,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(title)
                        .waiveraTextStyle(.titleSmall, weight: .bold)
                        .foregroundStyle(Palette.text)
                    Text(message)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.medium)
            .background(tone.containerColor, in: RoundedRectangle(cornerRadius: Radius.banner))
            .accessibilityElement(children: .combine)
        }
    }
#endif
