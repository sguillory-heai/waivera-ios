#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The month grid (always 42 cells) or the week strip (07 §1 "Grid"). Tapping a cell selects
    /// that date without changing the view.
    struct ScheduleGrid: View {
        let state: ScheduleUIState
        let onSelect: (GridCell) -> Void

        private let columns = Array(repeating: GridItem(.flexible(), spacing: Spacing.extraSmall), count: 7)

        var body: some View {
            VStack(spacing: Spacing.small) {
                if state.view == .month {
                    LazyVGrid(columns: columns, spacing: Spacing.extraSmall) {
                        ForEach(Array(state.weekdayHeaders.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol)
                                .font(WaiveraFont.eyebrow)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .accessibilityHidden(true)
                        }
                    }
                }
                LazyVGrid(columns: columns, spacing: Spacing.extraSmall) {
                    ForEach(state.cells) { cell in
                        DayCellView(cell: cell, isWeek: state.view == .week) { onSelect(cell) }
                    }
                }
            }
            .dynamicTypeSize(...CalendarMetrics.gridMaxTypeSize)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(ScheduleStrings.text("schedule.grid.label")))
        }
    }
#endif
