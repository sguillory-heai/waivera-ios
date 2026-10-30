#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One agenda card (concept A's sheet card: the surface at 20pt with a soft lift, no hairline).
    /// Titles wrap to two lines; the leading tile centres on a standard card and pins level with
    /// the title's first line once long content makes the card tall (leading-pin rule, v7 item 1).
    /// An ended item (today, before now) is quieter: secondary text, a neutral tile, no colour bar.
    struct AgendaCard: View {
        let row: AgendaRow
        let ended: Bool
        let openingWishes: Bool
        let canSendWishes: Bool
        let onOpenEvent: (String) -> Void
        let onSendWishes: (String) -> Void

        var body: some View {
            switch row.kind {
            case .event(let id):
                Button {
                    onOpenEvent(id)
                } label: {
                    EventCardBody(row: row, ended: ended)
                }
                .buttonStyle(.press(.card))
                .accessibilityLabel(Text(spokenLabel))
                .accessibilityHint(Text(ScheduleStrings.text("schedule.openEvent")))
            case .celebration(let celebration):
                MilestoneCard(
                    row: row,
                    celebration: celebration,
                    showsWishes: canSendWishes && !row.isMine,
                    isOpening: openingWishes,
                    onSendWishes: { onSendWishes(celebration.userId) }
                )
            case .holiday, .timeOff:
                InfoCardBody(row: row, ended: ended)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(spokenLabel))
            }
        }

        private var spokenLabel: String {
            ended
                ? ScheduleStrings.format(
                    "schedule.withDetail",
                    row.accessibilityLabel,
                    ScheduleStrings.text("schedule.ended")
                )
                : row.accessibilityLabel
        }
    }

    /// The title over its supporting lines: titleSmall, then labelMedium in secondary ink.
    private struct CardText: View {
        let title: String
        let lines: [String]
        let ended: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                    .waiveraTextStyle(.titleSmall)
                    .foregroundStyle(ended ? Palette.textSecondary : Palette.text)
                    .lineLimit(2)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .multilineTextAlignment(.leading)
        }
    }

    /// A pressable event: the owner's colour bar (accent when none; decoration only, the
    /// organizer is also named), a teal tile with a clock or a camera, the title, time and place,
    /// and the organizer.
    private struct EventCardBody: View {
        let row: AgendaRow
        let ended: Bool

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(spacing: 0) {
                (ended ? Palette.border : row.ownerColor.map { Color(serverColor: $0) } ?? Palette.accent)
                    .frame(width: CalendarMetrics.eventBar)
                LeadingPinLayout(
                    spacing: Spacing.mediumSmall,
                    standardHeight: LeadingPinLayout.standardHeight(
                        title: .titleSmall,
                        subtitle: .labelMedium,
                        dynamicTypeSize: dynamicTypeSize
                    )
                ) {
                    IconTile(
                        systemImage: row.isOnline ? "video" : "clock",
                        tone: ended ? .neutral : .teal,
                        size: ControlSize.cardTile,
                        glyphSize: ControlSize.cardTileGlyph
                    )
                    CardText(title: row.title, lines: [row.subtitle] + (row.owner.map { [$0] } ?? []), ended: ended)
                        .leadingPinContent()
                }
                .padding(Spacing.mediumSmall)
            }
            .frame(maxWidth: .infinity, minHeight: CalendarMetrics.eventCardMinHeight, alignment: .leading)
            .agendaSurface()
        }
    }

    /// A holiday (brand tile) or time off (teal tile) on the same lifted surface.
    private struct InfoCardBody: View {
        let row: AgendaRow
        let ended: Bool

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            LeadingPinLayout(
                spacing: Spacing.mediumSmall,
                standardHeight: LeadingPinLayout.standardHeight(
                    title: .titleSmall,
                    subtitle: .labelMedium,
                    dynamicTypeSize: dynamicTypeSize
                )
            ) {
                IconTile(
                    systemImage: row.kind == .holiday ? "calendar" : "beach.umbrella",
                    tone: ended ? .neutral : (row.kind == .holiday ? .brand : .teal),
                    size: ControlSize.cardTile,
                    glyphSize: ControlSize.cardTileGlyph
                )
                CardText(title: row.title, lines: [row.subtitle], ended: ended)
                    .leadingPinContent()
            }
            .padding(Spacing.mediumSmall + Spacing.xxSmall)
            .frame(maxWidth: .infinity, minHeight: ControlSize.listRowMinHeight, alignment: .leading)
            .agendaSurface()
        }
    }

    extension View {
        /// Concept A's sheet card: the surface at the sheet-card radius with the card lift.
        func agendaSurface() -> some View {
            let shape = RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
            return
                self
                .background(Palette.surface, in: shape)
                .clipShape(shape)
                .contentShape(shape)
                .shadow(
                    color: Palette.buttonRaise,
                    radius: Elevation.shadow(for: Elevation.card).radius,
                    x: 0,
                    y: Elevation.shadow(for: Elevation.card).y
                )
        }
    }
#endif
