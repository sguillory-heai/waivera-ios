#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct AttendeesSection: View {
        let details: EventDetailsUI

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ScheduleStrings.text("schedule.event.attendees"))
                        .waiveraTextStyle(.titleMedium)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.small)
                    Text(details.attendeeCount)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
                if details.attendees.isEmpty {
                    Text(ScheduleStrings.text("schedule.event.noAttendees"))
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
                ForEach(details.attendees) { person in
                    HStack(spacing: Spacing.smallPlus) {
                        MilestoneAvatarView(
                            name: person.name,
                            userId: person.userId,
                            celebration: person.celebration,
                            size: CalendarMetrics.attendeeAvatar
                        )
                        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                            NameText(
                                person.name,
                                style: .titleSmall,
                                lines: NameLines.listRow(dynamicTypeSize.category)
                            )
                            .foregroundStyle(Palette.text)
                            if let detail = person.detail {
                                Text(detail)
                                    .waiveraTextStyle(.labelMedium)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: ControlSize.minHitTarget)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(person.accessibilityLabel))
                }
            }
        }
    }
#endif
