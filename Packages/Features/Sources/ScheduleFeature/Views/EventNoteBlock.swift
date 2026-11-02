#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The event's details or its linked task (Android `LabeledBlock`): a muted card with a
    /// kicker over the text. The linked task takes the stronger violet edge.
    struct EventNoteBlock: View {
        let kicker: String
        let text: String
        let strongBorder: Bool

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(kicker)
                    .waiveraTextStyle(.kicker)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                Text(text)
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.text)
                    .textSelection(.enabled)
            }
            .padding(Spacing.mediumSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surfaceMuted, in: shape)
            .overlay(
                shape.strokeBorder(
                    strongBorder ? Palette.accentBorderStrong : Palette.border,
                    lineWidth: Spacing.hairline
                )
            )
            .accessibilityElement(children: .combine)
        }
    }
#endif
