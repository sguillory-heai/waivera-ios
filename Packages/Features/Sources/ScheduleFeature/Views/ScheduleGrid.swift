#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// The month grid (always 42 cells) or the week strip (07 §1 "Grid"). Each cell is one
    /// selectable control at least 44pt tall whose label says the date, whether it is today and
    /// what it holds, so the dots are never the only signal. Tapping a cell selects that date
    /// without changing the view.
    struct ScheduleGrid: View {
        let view: CalendarPeriod
        let cells: [GridCell]
        let weekdayHeaders: [String]
        var weekdayHeadersNarrow: [String] = []
        let onSelect: (CalendarDate) -> Void

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(spacing: 0) {
                if view == .month {
                    HStack(spacing: 0) {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, symbol in
                            Text(symbol)
                                .waiveraTextStyle(.eyebrow)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, Spacing.extraSmall)
                        }
                    }
                    .accessibilityHidden(true)
                }
                ForEach(weeks, id: \.first?.id) { week in
                    HStack(spacing: 0) {
                        ForEach(week) { cell in
                            DayCellView(cell: cell, isWeek: view == .week) { onSelect(cell.date) }
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .padding(.horizontal, Spacing.extraSmall)
            // Seven columns stop growing here so a two-digit day still fits its column; each
            // cell's spoken label and the agenda carry the same information at every size.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text(ScheduleStrings.text("schedule.grid.label")))
        }

        /// One letter at the accessibility sizes, where "Mon" no longer fits (Android `narrow`).
        private var headers: [String] {
            dynamicTypeSize.isExtraLargeText && weekdayHeadersNarrow.count == 7 ? weekdayHeadersNarrow : weekdayHeaders
        }

        private var weeks: [[GridCell]] {
            stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<min($0 + 7, cells.count)]) }
        }
    }
#endif
