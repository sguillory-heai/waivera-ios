#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct OrganizerBlock: View {
        let organizer: EventDetailsUI.Person
        let isMe: Bool

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(spacing: Spacing.smallPlus) {
                MilestoneAvatarView(
                    name: organizer.name,
                    userId: organizer.userId,
                    celebration: organizer.celebration,
                    size: CalendarMetrics.organizerAvatar
                )
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(ScheduleStrings.text("schedule.event.organizedBy"))
                        .waiveraTextStyle(.kicker)
                        .foregroundStyle(Palette.textSecondary)
                    NameText(
                        isMe ? ScheduleStrings.text("schedule.event.youOrganize") : organizer.name,
                        style: .titleSmall,
                        lines: NameLines.listRow(dynamicTypeSize.category)
                    )
                    .foregroundStyle(Palette.text)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.mediumSmall + Spacing.xxSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .agendaSurface()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(organizer.accessibilityLabel))
        }
    }
#endif
