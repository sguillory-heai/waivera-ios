#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// What the Today list can ask for. Navigation goes through `open`, which the screen maps
    /// to the router closures.
    struct TodayActions {
        var reload: () -> Void = {}
        var open: (TodayDestination, Int64?) -> Void = { _, _ in }
        var respond: (String, Bool) -> Void = { _, _ in }
        var toggleNeedsYou: () -> Void = {}
        var setFilter: (ActivityFilter) -> Void = { _ in }
        var toggleUnreadOnly: () -> Void = {}
        var markRead: (Int64) -> Void = { _ in }
        var markAllRead: () -> Void = {}
        var loadMore: () -> Void = {}
        var retryMore: () -> Void = {}
    }

    /// Formatters are costly to build, so every Today view shares one.
    @MainActor
    enum TodayFormatting {
        static let shared = TodayFormatter()
    }

    /// The stateless Today screen: one pull-to-refresh list in priority order. Loads under
    /// ~300 ms show nothing rather than flashing a skeleton.
    struct TodayContent: View {
        let state: TodayState
        let actions: TodayActions
        let onRefresh: @Sendable () async -> Void

        private var formatter: TodayFormatter { TodayFormatting.shared }

        var body: some View {
            LoadingContent(isLoading: state.isInitialLoad && state.loadError == nil) {
                list
            } skeleton: {
                TodaySkeleton()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background)
        }

        private var list: some View {
            List {
                dateHeader
                if let error = state.loadError {
                    EmptyStateView.error(
                        title: TodayStrings.text("today.error.title"),
                        message: error.userMessage,
                        onRetry: actions.reload
                    )
                    .todayListRow()
                } else {
                    needsYouRows
                    nextUpRows
                    celebrationRows
                    activityRows
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
            .accessibilityIdentifier("today.list")
        }

        // MARK: Date and quiet line

        @ViewBuilder private var dateHeader: some View {
            if let date = state.date {
                Text(formatter.longDay(date))
                    .font(WaiveraFont.subtitle)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.medium)
                    .padding(.top, Spacing.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .todayListRow()
            }
            if let quiet = state.quietStatus {
                QuietLine(text: formatter.quiet(quiet), systemImage: Self.icon(quiet))
                    .accessibilityIdentifier("today.quietLine")
                    .todayListRow()
            }
        }

        private static func icon(_ status: QuietStatus) -> String {
            switch status {
            case .offline: "wifi.slash"
            case .stale: "clock.arrow.circlepath"
            }
        }

        // MARK: Needs you

        @ViewBuilder private var needsYouRows: some View {
            let section = state.needsYou
            if state.isAllCaughtUp {
                AllCaughtUpView().todayListRow()
            } else if section.failed {
                TodaySectionHeader(title: TodayStrings.text("today.section.needsYou")).todayListRow()
                SectionErrorView(message: TodayStrings.text("today.needsYou.failed"), onRetry: actions.reload)
                    .todayListRow()
            } else if !section.items.isEmpty {
                TodaySectionHeader(title: TodayStrings.text("today.section.needsYou")).todayListRow()
                ForEach(section.items) { item in
                    NeedsYouRow(item: item, formatter: formatter, onOpen: actions.open, onRespond: actions.respond)
                        .todayListRow()
                }
                if section.hiddenCount > 0 || section.isExpanded {
                    TodayTextButton(
                        title: section.isExpanded
                            ? TodayStrings.text("today.needsYou.showLess")
                            : TodayStrings.showMore(section.hiddenCount),
                        action: actions.toggleNeedsYou
                    )
                    .padding(.horizontal, Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("today.needsYou.toggle")
                    .todayListRow()
                }
            }
        }

        // MARK: Next up

        @ViewBuilder private var nextUpRows: some View {
            let section = state.nextUp
            TodaySectionHeader(title: TodayStrings.text("today.section.nextUp")) {
                TodayTextButton(
                    title: TodayStrings.text("today.seeSchedule"),
                    hint: TodayStrings.text("today.seeSchedule.hint"),
                    action: { actions.open(.schedule, nil) }
                )
                .accessibilityIdentifier("today.seeSchedule")
            }
            .todayListRow()
            if section.failed {
                SectionErrorView(message: TodayStrings.text("today.nextUp.failed"), onRetry: actions.reload)
                    .todayListRow()
            } else if !section.isReady {
                SkeletonList(rows: 2).todayListRow()
            } else if section.items.isEmpty {
                QuietLine(text: TodayStrings.text("today.nextUp.empty")).todayListRow()
            } else {
                ForEach(section.items) { item in
                    NextUpRow(item: item, formatter: formatter) { actions.open(.event(id: item.eventId), nil) }
                        .todayListRow()
                }
            }
            if state.usesDeviceTimeZone {
                QuietLine(
                    text: TodayStrings.format("today.nextUp.deviceZone", state.timeZone.identifier),
                    systemImage: "globe"
                )
                .todayListRow()
            }
        }

        // MARK: Celebrations

        @ViewBuilder private var celebrationRows: some View {
            if !state.celebrations.isEmpty || state.celebrationsFailed {
                TodaySectionHeader(title: TodayStrings.text("today.section.celebrations")).todayListRow()
                if state.celebrationsFailed {
                    SectionErrorView(message: TodayStrings.text("today.celebration.failed"), onRetry: actions.reload)
                        .todayListRow()
                }
                ForEach(state.celebrations) { item in
                    CelebrationRow(item: item) { actions.open(.schedule, nil) }
                        .todayListRow()
                }
            }
        }

        // MARK: Activity

        @ViewBuilder private var activityRows: some View {
            let section = state.activity
            ActivityHeader(
                section: section,
                onSeeAll: { actions.open(.activity, nil) },
                onMarkAllRead: actions.markAllRead
            )
            .todayListRow()
            if section.failed {
                SectionErrorView(message: TodayStrings.text("today.activity.failed"), onRetry: actions.reload)
                    .todayListRow()
            } else if !section.isReady {
                SkeletonList(rows: 3).todayListRow()
            } else if section.isEmpty {
                EmptyStateView(
                    systemImage: "checkmark.circle",
                    title: TodayStrings.text("today.activity.empty.title"),
                    message: TodayStrings.text("today.activity.empty.message")
                )
                .todayListRow()
            } else {
                ActivityFilterBar(
                    filter: section.filter,
                    unreadOnly: section.unreadOnly,
                    onFilter: actions.setFilter,
                    onToggleUnread: actions.toggleUnreadOnly
                )
                .todayListRow()
                if section.isFilteredEmpty {
                    EmptyStateView(
                        systemImage: "magnifyingglass",
                        title: TodayStrings.text("today.activity.filtered.title"),
                        message: TodayStrings.text("today.activity.filtered.message")
                    )
                    .todayListRow()
                }
                ForEach(section.rows) { row in
                    ActivityItemRow(
                        row: row,
                        formatter: formatter,
                        onOpen: { actions.open(.chat(row.destination), row.id) },
                        onMarkRead: { actions.markRead(row.id) }
                    )
                    .todayListRow()
                }
                ActivityFooter(section: section, onLoadMore: actions.loadMore, onRetry: actions.retryMore)
                    .todayListRow()
            }
        }
    }

    extension View {
        /// Full-bleed list rows: the row draws its own padding and background.
        func todayListRow() -> some View {
            listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
#endif
