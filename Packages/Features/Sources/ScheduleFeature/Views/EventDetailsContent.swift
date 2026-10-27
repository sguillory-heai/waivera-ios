#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Header, notices, organizer, time and place, the invitation, Join, Message organizer and
    /// the attendees, in the 07 §7 order.
    struct EventDetailsContent: View {
        let details: EventDetailsUI
        let actions: EventActions

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                EventHeader(details: details)
                if let notice = details.refreshNotice {
                    BannerView(
                        .error,
                        message: notice,
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { actions.retry() }
                    )
                }
                if let organizer = details.organizer {
                    OrganizerBlock(organizer: organizer, isMe: details.isOrganizer)
                }
                EventFactsCard(details: details)
                if details.invitation != nil || details.invitationStatus != nil {
                    InvitationCard(details: details, actions: actions)
                }
                if details.join != nil {
                    JoinSection(details: details, actions: actions)
                }
                if details.canMessageOrganizer {
                    WaiveraButton(
                        ScheduleStrings.text("schedule.chat.organizer"),
                        variant: .secondary,
                        systemImage: "bubble.left.and.bubble.right",
                        isLoading: details.isOpeningChat,
                        action: { actions.messageOrganizer() }
                    )
                    if let error = details.chatError {
                        BannerView(.error, message: error)
                    }
                }
                AttendeesSection(details: details)
            }
        }
    }
#endif
