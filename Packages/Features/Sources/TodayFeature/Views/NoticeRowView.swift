#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A notification card, in the inbox and under Needs you (Android `NoticeRow`): the kind's
    /// tile, "Kind · time" in the kind's colour, the title, then the message. Unread cards are
    /// bold; a card that opens on the web shows the open-outside mark instead of the chevron.
    struct NoticeRowView: View {
        let row: NoticeRow
        let formatter: TodayFormatter
        let onOpen: () -> Void

        var body: some View {
            let tile = NoticeTile.of(row.kind)
            let kind = TodayStrings.noticeKind(row.kind)
            let headline = row.title.isEmpty ? kind : row.title
            let supporting = row.message.isEmpty || row.message == headline ? nil : row.message
            let spoken = TodayStrings.spoken(kind, headline, supporting, row.at.map(formatter.pastSpoken))
            TodayRow(
                eyebrow: TodayStrings.joined(kind, row.at.map(formatter.past)),
                eyebrowTint: tile.tone.contentColor,
                headline: headline,
                supporting: supporting,
                emphasized: row.isUnread,
                showsChevron: !row.opensOutside,
                accessibilityText: row.isUnread ? TodayStrings.format("today.activity.unreadPrefix", spoken) : spoken,
                accessibilityHintText: TodayStrings.text(
                    row.opensOutside ? "today.notices.hint.openWeb" : "today.notices.hint.open"
                ),
                action: onOpen,
                leading: { TodayTile(systemImage: tile.systemImage, tone: tile.tone) },
                trailing: {
                    if row.opensOutside {
                        Image(systemName: "arrow.up.right.square")
                            .font(WaiveraFont.captionEmphasis)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(Spacing.extraSmall)
                            .accessibilityHidden(true)
                    }
                }
            )
        }
    }
#endif
