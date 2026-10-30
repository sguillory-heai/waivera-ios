#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The full chat activity feed (mentions, replies, reactions), reached from Today: search,
    /// type chips with an Unread toggle, paging and Mark all read (06 §A).
    public struct ActivityView: View {
        let onOpenConversation: (_ conversationID: Int, _ targetMessageID: Int?) -> Void
        let onOpenThread: (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: ActivityFeedModel?

        public init(
            onOpenConversation: @escaping (_ conversationID: Int, _ targetMessageID: Int?) -> Void,
            onOpenThread: @escaping (_ rootMessageID: Int, _ conversationID: Int?, _ targetMessageID: Int?) -> Void
        ) {
            self.onOpenConversation = onOpenConversation
            self.onOpenThread = onOpenThread
        }

        public var body: some View {
            Group {
                if let model {
                    ActivityScreen(model: model, open: open)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TodayStrings.text("activity.title"))
            .navigationBarTitleDisplayMode(.inline)
            .task {
                let current =
                    model ?? data.map { ActivityFeedModel(environment: $0, clock: $0.clock) }
                if model == nil { model = current }
                await current?.run()
            }
        }

        private func open(_ destination: ChatDestination) {
            switch destination {
            case .conversation(let id, let target): onOpenConversation(id, target)
            case .thread(let root, let conversation, let target): onOpenThread(root, conversation, target)
            }
        }
    }

    private struct ActivityScreen: View {
        let model: ActivityFeedModel
        let open: (ChatDestination) -> Void
        @State private var query = ""

        var body: some View {
            ActivityContent(state: model.state, actions: actions, onRefresh: { [model] in await model.refresh() })
                .searchable(text: $query, prompt: Text(TodayStrings.text("today.activity.search")))
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .onChange(of: query) { model.setQuery(query) }
                .onChange(of: model.state.section.query) {
                    // Clear filters also clears the search field.
                    if model.state.section.query != query { query = model.state.section.query }
                }
                .todayFeedback(model.feedback, onAction: { model.retry($0) })
        }

        private var actions: ActivityActions {
            ActivityActions(
                reload: { model.retry(TodayToast(.refreshFailed)) },
                open: { row in
                    if let destination = model.open(row) { open(destination) }
                },
                setFilter: { model.setFilter($0) },
                toggleUnreadOnly: { model.toggleUnreadOnly() },
                clearFilters: { model.clearFilters() },
                markRead: { model.markRead($0) },
                markAllRead: { model.markAllRead() },
                loadMore: { model.loadMore() },
                retryMore: { model.retryMore() }
            )
        }
    }

    struct ActivityActions {
        var reload: () -> Void = {}
        var open: (ActivityRow) -> Void = { _ in }
        var setFilter: (ActivityFilter) -> Void = { _ in }
        var toggleUnreadOnly: () -> Void = {}
        var clearFilters: () -> Void = {}
        var markRead: (Int64) -> Void = { _ in }
        var markAllRead: () -> Void = {}
        var loadMore: () -> Void = {}
        var retryMore: () -> Void = {}
    }

    /// The stateless Activity screen, for the entry view, previews and snapshots.
    struct ActivityContent: View {
        let state: ActivityScreenState
        let actions: ActivityActions
        let onRefresh: @Sendable () async -> Void

        private var formatter: TodayFormatter { TodayFormatting.shared }

        var body: some View {
            LoadingContent(isLoading: state.isInitialLoad) {
                list
            } skeleton: {
                SkeletonList(rows: 6)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TodayStrings.text("today.activity.loading")))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background)
        }

        private var list: some View {
            List {
                if let quiet = state.quietStatus {
                    QuietLine(text: formatter.quiet(quiet), systemImage: "wifi.slash").todayListRow()
                }
                if let error = state.loadError {
                    EmptyStateView.error(
                        title: TodayStrings.text("today.activity.error.title"),
                        message: error.userMessage,
                        onRetry: actions.reload
                    )
                    .todayListRow()
                } else {
                    rows
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
            .accessibilityIdentifier("activity.list")
        }

        @ViewBuilder private var rows: some View {
            let section = state.section
            if section.isEmpty {
                EmptyStateView(
                    illustration: .activity,
                    title: TodayStrings.text("today.activity.caughtUp.title"),
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
                .padding(.top, Spacing.small)
                .todayListRow()
                ActivityMetaRow(section: section, onMarkAllRead: actions.markAllRead).todayListRow()
                if section.isFilteredEmpty {
                    EmptyStateView(
                        illustration: .search,
                        title: TodayStrings.text("today.activity.filtered.title"),
                        message: TodayStrings.text("today.activity.filtered.searchMessage"),
                        actionTitle: TodayStrings.text("today.activity.clearFilters"),
                        action: actions.clearFilters
                    )
                    .todayListRow()
                }
                ForEach(section.rows) { row in
                    ActivityItemRow(
                        row: row,
                        formatter: formatter,
                        onOpen: { actions.open(row) },
                        onMarkRead: { actions.markRead(row.id) }
                    )
                    .todayListRow()
                }
                ActivityFooter(section: section, onLoadMore: actions.loadMore, onRetry: actions.retryMore)
                    .todayListRow()
            }
        }
    }

    /// "{n} updates shown" with the unread badge and Mark all read.
    private struct ActivityMetaRow: View {
        let section: ActivitySection
        let onMarkAllRead: () -> Void

        var body: some View {
            let shown = section.rows.count
            ActivityHeader(
                section: section,
                title: TodayStrings.format(
                    shown == 1 ? "today.activity.shown.one" : "today.activity.shown.other",
                    String(shown)
                ),
                onMarkAllRead: onMarkAllRead
            )
        }
    }

    #if DEBUG
        #Preview("Light, demo data") {
            NavigationStack {
                ActivityView(onOpenConversation: { _, _ in }, onOpenThread: { _, _, _ in })
            }
            .fakeDataEnvironment()
        }

        #Preview("Dark") {
            NavigationStack {
                ActivityContent(state: TodayPreviewStates.activityScreen(), actions: ActivityActions(), onRefresh: {})
            }
            .preferredColorScheme(.dark)
        }

        #Preview("AX XXXL") {
            NavigationStack {
                ActivityContent(state: TodayPreviewStates.activityScreen(), actions: ActivityActions(), onRefresh: {})
            }
            .dynamicTypeSize(.accessibility5)
        }

        #Preview("Empty") {
            NavigationStack {
                ActivityView(onOpenConversation: { _, _ in }, onOpenThread: { _, _, _ in })
            }
            .fakeDataEnvironment(.empty)
        }
    #endif
#endif
