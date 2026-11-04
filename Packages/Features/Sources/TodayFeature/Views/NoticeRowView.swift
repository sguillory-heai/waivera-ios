#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One inbox row: the kind tile, the title (bold while unread), the message, the kind and age,
    /// and the open-outside mark for rows that open in the browser.
    struct NoticeRowView: View {
        let row: NoticeRow
        let formatter: TodayFormatter
        let onOpen: () -> Void

        var body: some View {
            let tile = NoticeTile.of(row.kind)
            let kind = TodayStrings.noticeKind(row.kind)
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                    IconTile(
                        systemImage: tile.systemImage,
                        tone: tile.tone,
                        size: ControlSize.fieldTile,
                        glyphSize: ControlSize.fieldTileGlyph
                    )
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(row.title)
                            .waiveraTextStyle(.titleSmall, weight: row.isUnread ? .bold : .medium)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                        if !row.message.isEmpty {
                            Text(row.message)
                                .waiveraTextStyle(.bodySmall)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(3)
                        }
                        Text(TodayStrings.joined(kind, row.at.map(formatter.past)))
                            .waiveraTextStyle(.labelSmall)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if row.opensOutside {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Palette.link)
                            .accessibilityHidden(true)
                    }
                    if row.isUnread {
                        UnreadDot(accessibilityLabel: TodayStrings.text("today.notices.unreadLabel"))
                            .padding(.top, Spacing.extraSmall)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.mediumSmall)
                .frame(minHeight: ControlSize.listRowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                Text(TodayStrings.text(row.opensOutside ? "today.notices.hint.openWeb" : "today.notices.hint.open"))
            )
        }
    }
#endif
