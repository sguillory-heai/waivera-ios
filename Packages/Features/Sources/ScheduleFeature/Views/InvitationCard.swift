#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Your answer, Decline / Accept, and the failure banner with Retry for the same answer.
    struct InvitationCard: View {
        let details: EventDetailsUI
        let actions: EventActions

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                Text(ScheduleStrings.text("schedule.response.heading"))
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                if let status = details.invitationStatus {
                    Text(status)
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let invitation = details.invitation, invitation.canChange {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.smallPlus) { buttons(invitation) }
                        VStack(spacing: Spacing.small) { buttons(invitation) }
                    }
                }
                if let failure = details.invitationFailure {
                    BannerView(
                        .error,
                        message: failure,
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { actions.retryResponse() }
                    )
                }
            }
            .padding(Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .waiveraAnimation(.state, value: details.invitation)
        }

        /// The chosen answer is the filled button; saving shows on it and blocks a second tap.
        @ViewBuilder private func buttons(_ invitation: InvitationUI) -> some View {
            let saving = invitation.phase == .saving
            WaiveraButton(
                ScheduleStrings.text("schedule.decline"),
                variant: invitation.response == .declined ? .primary : .secondary,
                systemImage: "xmark",
                isLoading: saving && invitation.response == .declined
            ) {
                actions.respond(false)
            }
            .disabled(saving)
            .accessibilityAddTraits(invitation.response == .declined ? .isSelected : [])
            WaiveraButton(
                ScheduleStrings.text("schedule.accept"),
                variant: invitation.response == .accepted ? .primary : .secondary,
                systemImage: "checkmark",
                isLoading: saving && invitation.response == .accepted
            ) {
                actions.respond(true)
            }
            .disabled(saving)
            .accessibilityAddTraits(invitation.response == .accepted ? .isSelected : [])
        }
    }
#endif
