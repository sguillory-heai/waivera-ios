#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct JoinSection: View {
        let details: EventDetailsUI
        let actions: EventActions

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                WaiveraButton(
                    ScheduleStrings.text("schedule.join"),
                    systemImage: "video.fill",
                    isLoading: details.join?.isBusy ?? false,
                    action: { actions.join() }
                )
                .disabled(details.join?.state != .open)
                if let note = details.joinNote {
                    Text(note)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
                if let error = details.joinError {
                    BannerView(.error, message: error, onDismiss: { actions.dismissJoinError() })
                }
            }
        }
    }
#endif
