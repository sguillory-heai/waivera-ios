#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One item in the Day view on concept B's timeline: its time ("Until" over the end of an
    /// item that began the day before, or "All day"), the rail's block in the item's tone, a
    /// tick down to the next item, then the card. At large text the time and a short block go
    /// above the card, which takes the full width. Week and Month keep the plain list.
    struct AgendaRailEntry<Content: View>: View {
        let rail: AgendaRail
        let tone: AgendaRailTone?
        let isLast: Bool
        @ViewBuilder let content: Content

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            if dynamicTypeSize.isLargeText {
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    HStack(spacing: Spacing.small) {
                        block(height: CalendarMetrics.railBlockShort)
                        if let kicker = rail.kicker {
                            Text(kicker).waiveraTextStyle(.timelineTime).foregroundStyle(Palette.textSecondary)
                        }
                        Text(rail.time).waiveraTextStyle(.timelineTime).foregroundStyle(Palette.text)
                    }
                    .accessibilityHidden(true)
                    content
                }
            } else {
                HStack(alignment: .top, spacing: Spacing.small) {
                    VStack(alignment: .trailing, spacing: 0) {
                        if let kicker = rail.kicker {
                            Text(kicker).foregroundStyle(Palette.textSecondary)
                        }
                        Text(rail.time).foregroundStyle(tone == nil ? Palette.textSecondary : Palette.text)
                    }
                    .waiveraTextStyle(.timelineTime)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.trailing)
                    .frame(width: ControlSize.timelineTimeColumn, alignment: .trailing)
                    .padding(.top, Spacing.mediumSmall)
                    .accessibilityHidden(true)
                    VStack(spacing: Spacing.extraSmall) {
                        block(height: CalendarMetrics.railBlockTall)
                        if !isLast {
                            Palette.border.frame(width: CalendarMetrics.railTick)
                        }
                    }
                    .padding(.top, Spacing.mediumSmall)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityHidden(true)
                    content
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }

        private func block(height: CGFloat) -> some View {
            RoundedRectangle(cornerRadius: Radius.timelineBlock, style: .continuous)
                .fill(tone?.color ?? Palette.borderStrong)
                .frame(width: ControlSize.timelineRailBlock, height: height)
        }
    }

    /// The thin "Now · 10:30 AM" line before the first item that has not ended (UI4-12). Solid
    /// accent, the same ink as its label (v5 rule A: no gradient off the hero).
    struct NowDivider: View {
        let time: String

        var body: some View {
            HStack(spacing: Spacing.small) {
                Text(ScheduleStrings.format("schedule.now", time))
                    .waiveraTextStyle(.labelMedium)
                    .foregroundStyle(Palette.accent)
                Capsule()
                    .fill(Palette.accent)
                    .frame(height: CalendarMetrics.nowLine)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(ScheduleStrings.format("schedule.now.a11y", time)))
        }
    }
#endif
