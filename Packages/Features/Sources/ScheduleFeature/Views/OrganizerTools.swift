#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The organizer's own tools: Edit and Cancel for a one-off event, or "Edit on web" with the
    /// reason for repeating and task meetings.
    struct OrganizerTools: View {
        let manage: ManageMode
        let details: EventDetailsUI
        let actions: EventActions

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                switch manage {
                case .edit:
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.small) { buttons }
                        VStack(spacing: Spacing.small) { buttons }
                    }
                    if let failure = details.cancelFailure {
                        BannerView(.error, message: failure, onDismiss: { actions.dismissCancelFailure() })
                    }
                case .webOnly:
                    if let editOnWeb = actions.editOnWeb {
                        WaiveraButton(
                            ScheduleStrings.text("schedule.editOnWeb"),
                            variant: .secondary,
                            systemImage: "safari",
                            fillsWidth: true,
                            action: { editOnWeb() }
                        )
                    }
                    Text(ScheduleStrings.text("schedule.editOnWeb.note"))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }

        @ViewBuilder private var buttons: some View {
            WaiveraButton(
                ScheduleStrings.text("schedule.editEvent"),
                variant: .secondary,
                size: .compact,
                systemImage: "pencil",
                fillsWidth: true,
                action: { actions.edit() }
            )
            .disabled(details.isCancelling)
            .accessibilityIdentifier("schedule.event.edit")
            WaiveraButton(
                ScheduleStrings.text("schedule.cancel.action"),
                variant: .destructiveOutline,
                size: .compact,
                systemImage: "calendar.badge.minus",
                isLoading: details.isCancelling,
                loadingTitle: ScheduleStrings.text("schedule.cancel.working"),
                fillsWidth: true,
                action: { actions.cancelEvent() }
            )
            .accessibilityIdentifier("schedule.event.cancel")
        }
    }
#endif
