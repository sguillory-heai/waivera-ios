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
            .padding(Spacing.mediumSmall + Spacing.xxSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .agendaSurface()
        }

        private func fact(systemImage: String, label: String, primary: String, secondary: String?) -> some View {
            HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                IconTile(
                    systemImage: systemImage,
                    tone: .teal,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    Text(ScheduleStrings.text(label))
                        .waiveraTextStyle(.fieldLabel)
                        .foregroundStyle(Palette.textSecondary)
                    Text(primary)
                        .waiveraTextStyle(.fieldValue)
                        .foregroundStyle(Palette.text)
                        .textSelection(.enabled)
                    if let secondary {
                        Text(secondary)
                            .waiveraTextStyle(.labelMedium)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            .accessibilityElement(children: .combine)
        }
    }
#endif
