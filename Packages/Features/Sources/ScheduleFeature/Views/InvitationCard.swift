#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Your answer: the kicker, what you said, "Not going" and "Going" as one single choice, and
    /// the failure banner with Retry for the same answer. The chosen answer is the selected
    /// button with a check that pops in; the other is the quiet unselected outline. Above 130%
    /// the pair stacks in the same order and drops the check so the labels stay whole. Saving
    /// shows on the chosen button, at its size, and blocks a second tap. Undo is the snackbar.
    struct InvitationCard: View {
        let details: EventDetailsUI
        let actions: EventActions

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                Text(ScheduleStrings.text("schedule.response.heading"))
                    .waiveraTextStyle(.kicker)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityAddTraits(.isHeader)
                if let status = details.invitationStatus {
                    SwapView(status) { text in
                        Text(text)
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.text)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let invitation = details.invitation, invitation.canChange || invitation.phase == .saving {
                    if dynamicTypeSize.isLargeText {
                        VStack(spacing: Spacing.small) { buttons(invitation, check: false) }
                    } else {
                        HStack(spacing: Spacing.small) { buttons(invitation, check: true) }
                    }
                }
                if let failure = details.invitationFailure {
                    BannerView(
                        .error,
                        title: ScheduleStrings.text("schedule.response.failed.title"),
                        message: failure,
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { actions.retryResponse() }
                    )
                }
            }
            .padding(Spacing.mediumSmall + Spacing.xxSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .agendaSurface()
            .waiveraAnimation(.state, value: details.invitation)
        }

        @ViewBuilder private func buttons(_ invitation: InvitationUI, check: Bool) -> some View {
            choice(invitation, accept: false, check: check)
            choice(invitation, accept: true, check: check)
        }

        private func choice(_ invitation: InvitationUI, accept: Bool, check: Bool) -> some View {
            let style = ResponseChoiceStyle.of(response: invitation.response, accept: accept)
            let saving = invitation.phase == .saving
            let chosen = style == .selected
            return WaiveraButton(
                ScheduleStrings.text(accept ? "schedule.accept" : "schedule.decline"),
                variant: style.variant,
                size: .compact,
                systemImage: chosen && check ? "checkmark" : nil,
                isLoading: saving && chosen,
                loadingTitle: ScheduleStrings.text("schedule.response.saving"),
                fillsWidth: true
            ) {
                actions.respond(accept)
            }
            .popOnChange(of: chosen)
            .disabled(saving)
            .accessibilityAddTraits(chosen ? .isSelected : [])
        }
    }

    extension ResponseChoiceStyle {
        var variant: WaiveraButtonVariant {
            switch self {
            case .primary: .primary
            case .tonal: .tonal
            case .selected: .selected
            case .unselected: .unselected
            }
        }
    }
#endif
