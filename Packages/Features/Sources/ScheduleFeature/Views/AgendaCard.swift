#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct AgendaCard: View {
        let row: AgendaRow
        let onOpenEvent: (String) -> Void

        var body: some View {
            if case .event(let id) = row.kind {
                Button {
                    onOpenEvent(id)
                } label: {
                    card
                }
                .buttonStyle(.pressScale)
                .accessibilityLabel(Text(row.accessibilityLabel))
                .accessibilityHint(Text(ScheduleStrings.text("schedule.openEvent")))
            } else {
                card
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(row.accessibilityLabel))
            }
        }

        private var card: some View {
            HStack(spacing: Spacing.smallPlus) {
                leading
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(row.title)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.text)
                    Text(row.subtitle)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .multilineTextAlignment(.leading)
                if case .event = row.kind {
                    Image(systemName: "chevron.right")
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, Spacing.smallPlus)
            .padding(.leading, isEvent ? Spacing.smallPlus + CalendarMetrics.eventBar : Spacing.smallPlus)
            .padding(.trailing, Spacing.smallPlus)
            .frame(minHeight: CalendarMetrics.eventCardMinHeight)
            .background(Palette.surface)
            .overlay(alignment: .leading) {
                if isEvent {
                    barColor.frame(width: CalendarMetrics.eventBar)
                }
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline))
            .contentShape(shape)
        }

        @ViewBuilder private var leading: some View {
            switch row.kind {
            case .celebration(let celebration):
                MilestoneAvatarView(
                    name: celebration.displayName ?? row.title,
                    userId: celebration.userId,
                    celebration: celebration,
                    size: CalendarMetrics.agendaAvatar
                )
            case .holiday:
                IconTile(systemImage: "calendar", tint: Palette.holiday)
            case .timeOff:
                IconTile(systemImage: "beach.umbrella.fill", tint: Palette.success)
            case .event:
                IconTile(systemImage: "clock")
            }
        }

        private var isEvent: Bool {
            if case .event = row.kind { return true }
            return false
        }

        private var barColor: Color {
            row.ownerColor.map { Color(serverColor: $0) } ?? Palette.accent
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
        }
    }
#endif
