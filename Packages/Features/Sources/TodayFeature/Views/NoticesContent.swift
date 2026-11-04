#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The stateless inbox, for the entry view, previews and snapshots.
    struct NoticesContent: View {
        let state: NoticesScreenState
        let actions: NoticesActions
        let onRefresh: @Sendable () async -> Void

        private var formatter: TodayFormatter { TodayFormatting.shared }

        var body: some View {
            LoadingContent(isLoading: state.phase == .loading) {
                list
            } skeleton: {
                SkeletonList(rows: 6)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TodayStrings.text("today.notices.loading")))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background)
        }

        private var list: some View {
            List {
                if state.isOffline {
                    QuietLine(text: TodayStrings.text("today.quiet.offline"), systemImage: "wifi.slash").todayListRow()
                }
                if state.phase == .error {
                    EmptyStateView.error(
                        title: TodayStrings.text("today.notices.error.title"),
                        message: state.error?.userMessage ?? "",
                        onRetry: actions.retry
                    )
                    .todayListRow()
                } else {
                    filters.todayListRow()
                    content
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
            .accessibilityIdentifier("notices.list")
        }

        private var filters: some View {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.small) {
                    ForEach(NoticeFilter.allCases, id: \.self) { filter in
                        ChipView(
                            TodayStrings.text("today.notices.filter.\(filter.rawValue)"),
                            isSelected: state.filter == filter
                        ) {
                            actions.setFilter(filter)
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.small)
            }
        }

        @ViewBuilder private var content: some View {
            if state.phase == .empty {
                if state.isFilteredEmpty {
                    EmptyStateView(
                        illustration: .search,
                        title: TodayStrings.text("today.notices.filtered.title"),
                        message: TodayStrings.text("today.notices.filtered.message"),
                        actionTitle: TodayStrings.text("today.notices.showAll"),
                        action: { actions.setFilter(.all) }
                    )
                    .todayListRow()
                } else {
                    EmptyStateView(
                        illustration: .caughtUp,
                        title: TodayStrings.text("today.notices.empty.title"),
                        message: TodayStrings.text("today.notices.empty.message")
                    )
                    .todayListRow()
                }
            } else {
                header.todayListRow()
                ForEach(state.groups) { group in
                    Text(dayTitle(group.day))
                        .waiveraTextStyle(.titleSmall)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.top, Spacing.medium)
                        .padding(.bottom, Spacing.extraSmall)
                        .accessibilityAddTraits(.isHeader)
                        .todayListRow()
                    ForEach(group.rows) { row in
                        NoticeRowView(row: row, formatter: formatter, onOpen: { actions.open(row.id) })
                            .todayListRow()
                    }
                }
            }
        }

        /// "3 unread" and Mark all read.
        private var header: some View {
            HStack(spacing: Spacing.small) {
                Text(TodayStrings.plural("today.notices.unread", state.unreadCount))
                    .waiveraTextStyle(.labelLarge)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if state.unreadCount > 0 {
                    WaiveraButton(
                        TodayStrings.text("today.notices.markAllRead"),
                        variant: .text,
                        isLoading: state.isMarkingAllRead,
                        action: actions.markAllRead
                    )
                }
            }
            .padding(.horizontal, Spacing.gutter)
        }

        private func dayTitle(_ day: NoticeDay) -> String {
            switch day {
            case .today: TodayStrings.text("today.notices.day.today")
            case .yesterday: TodayStrings.text("today.notices.day.yesterday")
            case .thisWeek: TodayStrings.text("today.notices.day.thisWeek")
            case .earlier: TodayStrings.text("today.notices.day.earlier")
            }
        }
    }
#endif
