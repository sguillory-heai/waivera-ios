#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Three event cards' worth of bones at the cards' own inset, surface, height and tile, so the
    /// loaded cards land exactly where the bones were. Shown only for loads slower than ~300 ms.
    struct AgendaSkeleton: View {
        private static let titleShares: [CGFloat] = [0.7, 0.55, 0.8]

        var body: some View {
            VStack(spacing: Spacing.small) {
                ForEach(Self.titleShares, id: \.self) { share in
                    HStack(spacing: Spacing.mediumSmall) {
                        SkeletonBlock(
                            width: ControlSize.cardTile,
                            height: ControlSize.cardTile,
                            cornerRadius: Radius.tile
                        )
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            GeometryReader { proxy in
                                SkeletonBlock(width: proxy.size.width * share)
                            }
                            .frame(height: ControlSize.skeletonLine)
                            GeometryReader { proxy in
                                SkeletonBlock(width: proxy.size.width / 2)
                            }
                            .frame(height: ControlSize.skeletonLine)
                        }
                    }
                    .padding(Spacing.mediumSmall)
                    .padding(.leading, CalendarMetrics.eventBar)
                    .frame(maxWidth: .infinity, minHeight: CalendarMetrics.eventCardMinHeight)
                    .agendaSurface()
                }
            }
            .accessibilityElement()
            .accessibilityLabel(Text(ScheduleStrings.text("schedule.loading")))
        }
    }
#endif
