#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The Week and Month agenda's day heading on a plain card: a teal calendar tile, the day,
    /// and the Today badge. The day moves with the grid: a period step slides it the same way,
    /// and a day picked in the same period swaps in place (M2-11). From the largest sizes it
    /// reads "Sun, Nov 1" so the day number never stands alone (UI11-04); VoiceOver hears it whole.
    struct AgendaHeader: View {
        let state: ScheduleUIState

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            SwapView(
                state.selectedDate,
                axis: state.periodStep == 0 ? nil : .horizontal,
                forward: state.periodStep >= 0
            ) {
                _ in
                HStack(spacing: Spacing.mediumSmall) {
                    IconTile(systemImage: "calendar", tone: .teal)
                    Text(dynamicTypeSize.isExtraLargeText ? state.agendaHeadingShort : state.agendaHeading)
                        .waiveraTextStyle(.titleMedium)
                        .foregroundStyle(Palette.text)
                        .accessibilityLabel(Text(state.agendaHeading))
                        .accessibilityAddTraits(.isHeader)
                    if state.isTodaySelected {
                        StatusBadge(ScheduleStrings.text("schedule.today"), tone: .accent)
                    }
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, Spacing.mediumSmall)
            .padding(.vertical, Spacing.small)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous))
        }
    }
#endif
