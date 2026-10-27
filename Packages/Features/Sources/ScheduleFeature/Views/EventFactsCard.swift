#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Time, place, details and the linked task in one card.
    struct EventFactsCard: View {
        let details: EventDetailsUI

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                fact(
                    systemImage: "clock",
                    label: "schedule.event.time",
                    primary: details.timePrimary,
                    secondary: details.timeSecondary
                )
                if details.isOnline || details.location != nil {
                    fact(
                        systemImage: details.isOnline ? "video" : "mappin.and.ellipse",
                        label: details.isOnline ? "schedule.event.online" : "schedule.event.location",
                        primary: details.location ?? ScheduleStrings.text("schedule.event.online"),
                        secondary: nil
                    )
                }
                if let text = details.details {
                    fact(systemImage: "text.alignleft", label: "schedule.event.details", primary: text, secondary: nil)
                }
                if let task = details.taskTitle {
                    fact(systemImage: "checklist", label: "schedule.event.linkedTask", primary: task, secondary: nil)
                }
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
        }

        private func fact(systemImage: String, label: String, primary: String, secondary: String?) -> some View {
            HStack(alignment: .top, spacing: Spacing.smallPlus) {
                Image(systemName: systemImage)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.accent)
                    .frame(width: ControlSize.smallIcon)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(ScheduleStrings.text(label))
                        .font(WaiveraFont.captionEmphasis)
                        .foregroundStyle(Palette.textSecondary)
                    Text(primary)
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                    if let secondary {
                        Text(secondary)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
