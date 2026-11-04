#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The notifications inbox, the same list as the web bell: Tasks, Approvals and Meetings
    /// chips, day groups, Mark all read and the caught-up state. Rows open their task, request,
    /// event or web page and are marked read.
    public struct NoticesView: View {
        let onOpen: (NoticeDestination) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: NoticesModel?

        public init(onOpen: @escaping (NoticeDestination) -> Void) {
            self.onOpen = onOpen
        }

        public var body: some View {
            Group {
                if let model {
                    NoticesScreen(model: model, onOpen: onOpen)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TodayStrings.text("notices.title"))
            .waiveraTopBar(TodayStrings.text("notices.title"))
            .task {
                let current = model ?? data.map { NoticesModel(environment: $0, clock: $0.clock) }
                if model == nil { model = current }
                await current?.run()
            }
        }
    }

    private struct NoticesScreen: View {
        let model: NoticesModel
        let onOpen: (NoticeDestination) -> Void

        var body: some View {
            NoticesContent(
                state: model.state,
                actions: NoticesActions(
                    open: { id in
                        if let destination = model.open(id) { onOpen(destination) }
                    },
                    setFilter: { model.setFilter($0) },
                    markAllRead: { model.markAllRead() },
                    retry: { Task { await model.refresh() } }
                ),
                onRefresh: { [model] in await model.refresh() }
            )
            .todayFeedback(model.feedback, onAction: { model.retry($0) })
        }
    }

    struct NoticesActions {
        var open: (String) -> Void = { _ in }
        var setFilter: (NoticeFilter) -> Void = { _ in }
        var markAllRead: () -> Void = {}
        var retry: () -> Void = {}
    }

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

    /// One inbox row: the kind tile, the title (bold while unread), the message, the kind and age,
    /// and the open-outside mark for rows that open in the browser.
    struct NoticeRowView: View {
        let row: NoticeRow
        let formatter: TodayFormatter
        let onOpen: () -> Void

        var body: some View {
            let tile = NoticeTile.of(row.kind)
            let kind = TodayStrings.noticeKind(row.kind)
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                    IconTile(
                        systemImage: tile.systemImage,
                        tone: tile.tone,
                        size: ControlSize.fieldTile,
                        glyphSize: ControlSize.fieldTileGlyph
                    )
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(row.title)
                            .waiveraTextStyle(.titleSmall, weight: row.isUnread ? .bold : .medium)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                        if !row.message.isEmpty {
                            Text(row.message)
                                .waiveraTextStyle(.bodySmall)
                                .foregroundStyle(Palette.textSecondary)
                                .lineLimit(3)
                        }
                        Text(TodayStrings.joined(kind, row.at.map(formatter.past)))
                            .waiveraTextStyle(.labelSmall)
                            .foregroundStyle(Palette.textTertiary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if row.opensOutside {
                        Image(systemName: "arrow.up.right.square")
                            .foregroundStyle(Palette.link)
                            .accessibilityHidden(true)
                    }
                    if row.isUnread {
                        UnreadDot(accessibilityLabel: TodayStrings.text("today.notices.unreadLabel"))
                            .padding(.top, Spacing.extraSmall)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.mediumSmall)
                .frame(minHeight: ControlSize.listRowMinHeight)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                Text(TodayStrings.text(row.opensOutside ? "today.notices.hint.openWeb" : "today.notices.hint.open"))
            )
        }
    }

    /// The glyph and tint for each kind of notification: one meaning per tint.
    enum NoticeTile {
        static func of(_ kind: NoticeKind) -> (systemImage: String, tone: TileTone) {
            switch kind {
            case .taskAssigned: ("checklist", .brand)
            case .taskActivity: ("text.bubble", .brand)
            case .approval: ("checkmark.seal", .amber)
            case .signature: ("signature", .amber)
            case .survey: ("list.clipboard", .teal)
            case .meeting: ("calendar", .teal)
            case .timeOff: ("sun.max", .teal)
            case .other: ("bell", .neutral)
            }
        }
    }

    #if DEBUG
        #Preview("Inbox, demo data") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment()
        }

        #Preview("Inbox, dark") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment()
                .preferredColorScheme(.dark)
        }

        #Preview("Inbox, AX XXXL") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }

        #Preview("Inbox, empty") {
            NavigationStack { NoticesView(onOpen: { _ in }) }
                .fakeDataEnvironment(.empty)
        }
    #endif
#endif
