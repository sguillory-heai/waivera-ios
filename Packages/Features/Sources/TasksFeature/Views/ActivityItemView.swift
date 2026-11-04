#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One logged activity in the original layout: the action leads as the headline beside the
    /// activity tile, then when and who, then the note. Your own entries tag "You" after the
    /// action instead of your name. Time spent is left out, as on the web: it feeds reporting.
    struct ActivityItemView: View {
        let row: ActivityRow

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                IconTile(
                    systemImage: "checklist",
                    tone: row.isNew ? .teal : .brand,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    ActivityHeadline(type: row.type, mine: row.byMe)
                    if !meta.isEmpty {
                        // Time first, so a long name is the part that is cut.
                        Text(meta)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    if let description = row.description {
                        ActivityNote(text: description)
                            .padding(.top, Spacing.extraSmall)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.minHitTarget, alignment: .leading)
        }

        private var meta: String {
            [row.moment?.text, row.byMe ? nil : row.author].compactMap(\.self).joined(separator: " · ")
        }
    }
#endif
