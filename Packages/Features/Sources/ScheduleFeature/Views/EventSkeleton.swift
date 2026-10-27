#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Shaped like the loaded screen: title, organizer, time card and invitation.
    struct EventSkeleton: View {
        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                SkeletonBlock(height: ControlSize.skeletonLine * 2).padding(.trailing, Spacing.huge)
                SkeletonBlock(height: ControlSize.iconTile, cornerRadius: Radius.card)
                SkeletonBlock(height: ControlSize.iconTile * 2, cornerRadius: Radius.card)
                SkeletonBlock(height: ControlSize.buttonHeight, cornerRadius: Radius.button)
            }
            .padding(Spacing.medium)
            .accessibilityElement()
            .accessibilityLabel(Text(ScheduleStrings.text("schedule.event.loading")))
        }
    }
#endif
