#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct OrganizerBlock: View {
        let organizer: EventDetailsUI.Person
        let isMe: Bool

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
                        .textCase(.uppercase)
                        .font(WaiveraFont.eyebrow)
                        .foregroundStyle(Palette.accent)
                    Text(isMe ? ScheduleStrings.text("schedule.event.youOrganize") : organizer.name)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.text)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.smallPlus)
            .background(Palette.accentSoft, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(organizer.accessibilityLabel))
        }
    }
#endif
