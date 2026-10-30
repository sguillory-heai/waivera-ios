#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The schedule screen drawn from plain state, so previews and snapshots render every state
    /// without a data layer.
    public struct ScheduleScreenView: View {
        let state: ScheduleUIState
        let actions: ScheduleActions
        let refresh: @Sendable () async -> Void

        public init(
            state: ScheduleUIState,
            actions: ScheduleActions = ScheduleActions(),
            refresh: @escaping @Sendable () async -> Void = {}
        ) {
            self.state = state
            self.actions = actions
            self.refresh = refresh
        }

        public var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(ScheduleStrings.subtitle)
                        .font(WaiveraFont.subtitle)
                        .foregroundStyle(Palette.textSecondary)
                    SegmentedChips(options: viewOptions, selection: viewSelection)
                        .padding(.horizontal, -Spacing.medium)
                        .accessibilityLabel(Text(ScheduleStrings.text("schedule.view.label")))
                    PeriodNavigator(title: state.title, onStep: { actions.step($0) })
                    notices
                    if state.view != .day {
                        ScheduleGrid(state: state) { actions.selectDate($0.date) }
                    }
                    AgendaSection(
                        heading: state.agendaHeading,
                        agenda: state.agenda,
                        onOpenEvent: { actions.openEvent($0) },
                        onRetry: { actions.retry() }
                    )
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.large)
            }
            .background(Palette.background)
            .refreshable { [refresh] in await refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(ScheduleStrings.text("schedule.today"), action: { actions.goToToday() })
                        .font(WaiveraFont.label)
                        .foregroundStyle(Palette.accent)
                        .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                        .accessibilityHint(Text(ScheduleStrings.text("schedule.today.hint")))
                }
            }
            .waiveraAnimation(.state, value: state.selectedDate)
        }

        @ViewBuilder private var notices: some View {
            if let notice = state.zoneNotice {
                Label(notice, systemImage: "globe")
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
            if let notice = state.feedNotice {
                BannerView(
                    .error,
                    message: notice,
                    actionTitle: ScheduleStrings.text("schedule.retry"),
                    action: { actions.retry() }
                )
            }
            if state.milestonesFailed {
                BannerView(
                    .info,
                    message: ScheduleStrings.text("schedule.milestonesFailed"),
                    actionTitle: ScheduleStrings.text("schedule.retry"),
                    action: { actions.retryMilestones() }
                )
            }
        }

        private var viewOptions: [SegmentedChips<CalendarPeriod>.Option] {
            [
                .init(.day, title: ScheduleStrings.text("schedule.view.day")),
                .init(.week, title: ScheduleStrings.text("schedule.view.week")),
                .init(.month, title: ScheduleStrings.text("schedule.view.month")),
            ]
        }

        private var viewSelection: Binding<CalendarPeriod> {
            // Captures only Sendable values: Binding's closures are @Sendable.
            let current = state.view
            let select = actions.selectView
            return Binding(get: { current }, set: { select($0) })
        }
    }
#endif
