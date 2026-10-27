#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    struct DayCellView: View {
        let cell: GridCell
        let isWeek: Bool
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                VStack(spacing: Spacing.extraSmall) {
                    if isWeek {
                        Text(cell.weekday)
                            .font(WaiveraFont.eyebrow)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Text(cell.dayNumber)
                        .font(isWeek ? WaiveraFont.sectionTitle : WaiveraFont.bodyEmphasis)
                        .fontWeight(cell.isToday ? .heavy : nil)
                        .foregroundStyle(numberColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    DayDots(marker: cell.marker)
                }
                .padding(.vertical, Spacing.extraSmall)
                .frame(
                    maxWidth: .infinity,
                    minHeight: isWeek ? CalendarMetrics.weekCellMinHeight : ControlSize.minHitTarget
                )
                .aspectRatio(isWeek ? nil : 1, contentMode: .fit)
                .background(cell.isSelected ? Palette.accentSoft : Color.clear, in: shape)
                .overlay(
                    shape.strokeBorder(
                        cell.isToday ? Palette.accent : Color.clear,
                        lineWidth: CalendarMetrics.todayBorder
                    )
                )
                .contentShape(shape)
            }
            .buttonStyle(.pressScale)
            .accessibilityLabel(Text(cell.accessibilityLabel))
            .accessibilityAddTraits(cell.isSelected ? [.isSelected] : [])
            .waiveraAnimation(.state, value: cell.isSelected)
        }

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: isWeek ? Radius.card : Radius.button, style: .continuous)
        }

        private var numberColor: Color {
            if cell.isSelected { return Palette.accent }
            return cell.inPeriod ? Palette.text : Palette.textSecondary
        }
    }
#endif
