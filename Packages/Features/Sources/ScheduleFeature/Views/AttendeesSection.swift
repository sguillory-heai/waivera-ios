#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct AttendeesSection: View {
        let details: EventDetailsUI

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(alignment: .firstTextBaseline) {
                    Text(ScheduleStrings.text("schedule.event.attendees"))
                        .font(WaiveraFont.sectionTitle)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer(minLength: Spacing.small)
                    Text(details.attendeeCount)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                if details.attendees.isEmpty {
                    Text(ScheduleStrings.text("schedule.event.noAttendees"))
                        .font(WaiveraFont.body)
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
                            Text(person.name)
                                .font(WaiveraFont.bodyEmphasis)
                                .foregroundStyle(Palette.text)
                            if let detail = person.detail {
                                Text(detail)
                                    .font(WaiveraFont.caption)
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
