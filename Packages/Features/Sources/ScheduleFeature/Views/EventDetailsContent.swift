#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The loaded event in Android's `EventBody` order: what it is and when first, then what the
    /// person can do (answer, join, message the organizer), then who organizes it and who is
    /// coming. A failed refresh is a warning with a title, since the saved copy still shows.
    struct EventDetailsContent: View {
        let details: EventDetailsUI
        let actions: EventActions

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                EventHeader(details: details)
                EventFactsCard(details: details)
                if let notice = details.refreshNotice {
                    BannerView(
                        .warning,
                        title: ScheduleStrings.text("schedule.event.refreshFailed.title"),
                        message: notice,
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { actions.retry() }
                    )
                }
                if details.invitation != nil || details.invitationStatus != nil {
                    InvitationCard(details: details, actions: actions)
                }
                if details.join != nil {
                    JoinSection(details: details, actions: actions)
                }
                if details.canMessageOrganizer {
                    // Tonal with an accent glyph: an outlined block read as the heaviest thing
                    // on the screen (Android).
                    WaiveraButton(
                        ScheduleStrings.text("schedule.chat.organizer"),
                        variant: .tonal,
                        systemImage: "bubble.left.and.bubble.right",
                        isLoading: details.isOpeningChat,
                        loadingTitle: ScheduleStrings.text("schedule.openingChat"),
                        fillsWidth: true,
                        action: { actions.messageOrganizer() }
                    )
                    if let error = details.chatError {
                        BannerView(.error, message: error)
                    }
                }
                if let organizer = details.organizer {
                    OrganizerBlock(organizer: organizer, isMe: details.isOrganizer)
                }
                AttendeesSection(details: details)
            }
        }
    }
#endif
