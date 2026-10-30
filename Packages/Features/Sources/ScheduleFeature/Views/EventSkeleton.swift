#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Shaped like the loaded event (Android `EventBodySkeleton`): the title and two shorter
    /// lines, then rows like the attendees'. Spoken once as "Loading event…".
    struct EventSkeleton: View {
        private static let lineFractions: [CGFloat] = [0.7, 0.5, 0.35]

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    ForEach(Array(Self.lineFractions.enumerated()), id: \.offset) { _, fraction in
                        SkeletonBlock(height: ControlSize.skeletonLine)
                            .containerRelativeFrame(.horizontal, alignment: .leading) { width, _ in
                                (width - 2 * Spacing.gutter) * fraction
                            }
                    }
                }
                .padding([.horizontal, .top], Spacing.gutter)
                SkeletonList(rows: 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ScheduleStrings.text("schedule.event.loading")))
        }
    }
#endif
