#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// An accent circle for events and a milestone diamond for celebrations: two shapes, so the
    /// marker is never colour-only. The row keeps its height when empty so cells line up.
    struct DayDots: View {
        let marker: DayMarker

        var body: some View {
            HStack(spacing: CalendarMetrics.dotGap) {
                if marker.events > 0 {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: CalendarMetrics.dot, height: CalendarMetrics.dot)
                }
                if marker.celebrations > 0 {
                    Rectangle()
                        .fill(Palette.milestone)
                        .frame(width: CalendarMetrics.dot, height: CalendarMetrics.dot)
                        .rotationEffect(.degrees(45))
                }
            }
            .frame(minHeight: CalendarMetrics.dot)
            .accessibilityHidden(true)
        }
    }
#endif
