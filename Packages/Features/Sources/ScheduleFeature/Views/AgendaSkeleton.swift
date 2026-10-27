#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Shaped like the agenda cards, shown only for loads slower than ~300 ms.
    struct AgendaSkeleton: View {
        var body: some View {
            VStack(spacing: Spacing.small) {
                ForEach(0..<3, id: \.self) { _ in
                    HStack(spacing: Spacing.smallPlus) {
                        SkeletonBlock(
                            width: ControlSize.iconTile,
                            height: ControlSize.iconTile,
                            cornerRadius: Radius.button
                        )
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            SkeletonBlock()
                            SkeletonBlock().padding(.trailing, Spacing.huge)
                        }
                    }
                    .padding(Spacing.smallPlus)
                    .frame(minHeight: CalendarMetrics.eventCardMinHeight)
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(ScheduleStrings.text("schedule.loading")))
        }
    }
#endif
