#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// Previous, the period title, next; the saved zone is a quiet caption under the title. In
    /// the Day view the title is the only day heading, so it carries the Today badge, which moves
    /// under the title at large text so the title keeps the width between the arrows (UI5-04).
    /// From the largest sizes the Day title shortens its month ("Sun, Nov 1", UI10-09). The title
    /// slides the way the period moved.
    struct PeriodRow: View {
        let state: ScheduleUIState
        let onStep: (Int) -> Void

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            let showToday = state.view == .day && state.isTodaySelected
            VStack(spacing: Spacing.extraSmall) {
                HStack(spacing: 0) {
                    stepButton(systemImage: "chevron.left", label: "schedule.previous", direction: -1)
                    HStack(spacing: Spacing.small) {
                        SwapView(
                            state.period,
                            axis: state.periodStep == 0 ? nil : .horizontal,
                            forward: state.periodStep >= 0
                        ) {
                            _ in
                            Text(dynamicTypeSize.isExtraLargeText ? state.shortTitle : state.title)
                                .waiveraTextStyle(.titleMedium)
                                .foregroundStyle(Palette.text)
                                .multilineTextAlignment(.center)
                                .accessibilityLabel(Text(state.title))
                                .accessibilityAddTraits(.isHeader)
                        }
                        if showToday && !dynamicTypeSize.isLargeText {
                            StatusBadge(ScheduleStrings.text("schedule.today"), tone: .accent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .clipped()
                    stepButton(systemImage: "chevron.right", label: "schedule.next", direction: 1)
                }
                if showToday && dynamicTypeSize.isLargeText {
                    StatusBadge(ScheduleStrings.text("schedule.today"), tone: .accent)
                }
                if let notice = state.zoneNotice, !state.isFallbackZone {
                    Text(notice)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, Spacing.extraSmall)
            .padding(.vertical, Spacing.extraSmall + Spacing.xxSmall)
        }

        private func stepButton(systemImage: String, label: String, direction: Int) -> some View {
            Button {
                onStep(direction)
            } label: {
                Image(systemName: systemImage)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.text)
                    .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.compact))
            .accessibilityLabel(Text(ScheduleStrings.text(label)))
        }
    }
#endif
