#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One day (v5 decision 4, option C): the selected day is a soft lilac rounded square with its
    /// number in bold violet, so the selection reads by ink and weight as well as tint. Today is a
    /// bold violet number (and weekday, in the week strip) with a short violet dash under it. The
    /// weekday never sits inside the selection. The picked square pops in; the one it leaves fades.
    struct DayCellView: View {
        let cell: GridCell
        let isWeek: Bool
        let onTap: () -> Void

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @State private var pops = 0

        var body: some View {
            Button(action: onTap) {
                VStack(spacing: Spacing.xxSmall) {
                    if isWeek {
                        Text(cell.weekday)
                            .waiveraTextStyle(.eyebrow)
                            .fontWeight(cell.isToday ? .heavy : nil)
                            .foregroundStyle(cell.isToday ? Palette.link : Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    square
                    dots
                }
                .padding(.vertical, Spacing.extraSmall)
                .frame(
                    maxWidth: .infinity,
                    minHeight: isWeek ? CalendarMetrics.weekCellMinHeight : ControlSize.minHitTarget
                )
                .padding(Spacing.xxSmall)
                .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
            }
            .buttonStyle(.press(.compact))
            .accessibilityLabel(Text(cell.accessibilityLabel))
            .accessibilityAddTraits(cell.isSelected ? [.isSelected] : [])
            .onChange(of: cell.isSelected) { _, selected in
                if selected { pops += 1 }
            }
        }

        /// The number with today's dash slot under it, inside the square on every day, so the
        /// numbers in a row share a line whether or not one of them is today.
        private var square: some View {
            let side = isWeek ? CalendarMetrics.daySquareLarge : CalendarMetrics.daySquare
            return VStack(spacing: CalendarMetrics.todayDashGap) {
                Text(cell.dayNumber)
                    .waiveraTextStyle(isWeek ? .titleLarge : .titleSmall)
                    .fontWeight(cell.isToday || cell.isSelected ? .heavy : .semibold)
                    .foregroundStyle(numberColor)
                    .lineLimit(1)
                    .fixedSize()
                Capsule()
                    .fill(cell.isToday ? Palette.todayMark : Color.clear)
                    .frame(width: CalendarMetrics.todayDashWidth, height: CalendarMetrics.todayDashHeight)
            }
            .padding(.horizontal, Spacing.extraSmall)
            .padding(.vertical, CalendarMetrics.todayDashInset)
            .frame(minWidth: side, minHeight: side)
            .background {
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(Palette.dayTint)
                    .opacity(cell.isSelected ? 1 : 0)
            }
            .waiveraAnimation(.state, value: cell.isSelected)
            .popOnChange(of: pops)
        }

        /// One circle for events and a diamond for celebrations: two shapes, so the marker is
        /// never colour-only. The row keeps its height when empty so cells line up.
        private var dots: some View {
            HStack(spacing: CalendarMetrics.dotGap) {
                if cell.marker.events > 0 {
                    Circle()
                        .fill(Palette.accent)
                        .frame(width: CalendarMetrics.dot, height: CalendarMetrics.dot)
                }
                if cell.marker.celebrations > 0 {
                    Rectangle()
                        .fill(Palette.milestone)
                        .frame(width: CalendarMetrics.milestoneDot, height: CalendarMetrics.milestoneDot)
                        .rotationEffect(.degrees(45))
                        .scaleEffect(1 / 2.squareRoot())
                }
            }
            .frame(minHeight: CalendarMetrics.milestoneDot)
            .accessibilityHidden(true)
        }

        private var numberColor: Color {
            if cell.isSelected { return Palette.onDayTint }
            if cell.isToday { return Palette.link }
            // The other month's dates recede, so this month's read as the grid (UI10-16).
            return cell.inPeriod ? Palette.text : Palette.textTertiary
        }
    }
#endif
