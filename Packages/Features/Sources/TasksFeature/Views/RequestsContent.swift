#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Which list the screen shows: requests waiting on the person (the tab), or their own (a page).
    enum RequestsMode: Sendable {
        case waiting, mine
    }

    /// The stateless Requests list (Android `RequestsContent`). Waiting shows only what needs the
    /// person's decision; their own requests are one quiet row after the last card, or a small
    /// button under the caught-up art, so they never read as more work to review.
    struct RequestsContent: View {
        let state: RequestsScreenState
        let actions: RequestsActions
        var mode: RequestsMode = .waiting
        let onRefresh: @Sendable () async -> Void

        var body: some View {
            List {
                switch mode {
                case .waiting: waiting
                case .mine: mine
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
            .accessibilityIdentifier(mode == .waiting ? "requests.list" : "requests.mine")
        }

        @ViewBuilder private var waiting: some View {
            switch state.waiting {
            case .loading:
                loading
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.requests.waitingError"),
                    message: "",
                    onRetry: actions.retryWaiting
                )
                .tasksListRow()
                RequestsMineRow(mine: state.mine, onOpen: actions.openMine).tasksListRow()
                webFooter
            case .ready(let list) where list.isEmpty:
                RequestsCaughtUp(onOpenMine: actions.openMine).tasksListRow()
            case .ready(let list):
                CountedSectionHeader(
                    TasksStrings.text("tasks.requests.waiting"),
                    count: list.count,
                    countLabel: TasksStrings.plural("tasks.segment.waiting", list.count)
                )
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.medium)
                .padding(.bottom, Spacing.extraSmall)
                .tasksListRow()
                ForEach(list) { item in
                    RequestCard(item: item, waiting: true) { actions.review(item) }
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.extraSmall)
                        .tasksListRow()
                }
                RequestsMineRow(mine: state.mine, onOpen: actions.openMine).tasksListRow()
                webFooter
            }
        }

        @ViewBuilder private var mine: some View {
            switch state.mine {
            case .loading:
                loading
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.requests.mineError"),
                    message: "",
                    onRetry: actions.retryMine
                )
                .tasksListRow()
            case .ready(let list) where list.isEmpty:
                EmptyStateView(
                    illustration: .search,
                    title: TasksStrings.text("tasks.requests.mineEmptyTitle"),
                    message: TasksStrings.text("tasks.requests.mineEmptyMessage")
                )
                .tasksListRow()
            case .ready(let list):
                let pending = list.filter { $0.request.status == .pending }
                let decided = list.filter { $0.request.status != .pending }
                mineGroup(TasksStrings.text("tasks.requests.pending"), rows: pending, counted: true)
                mineGroup(TasksStrings.text("tasks.requests.decided"), rows: decided, counted: false)
                Text(TasksStrings.text("tasks.requests.mineNote"))
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.gutter + Spacing.extraSmall)
                    .padding(.top, Spacing.small)
                    .padding(.bottom, Spacing.large)
                    .tasksListRow()
            }
        }

        @ViewBuilder
        private func mineGroup(_ title: String, rows: [RequestItem], counted: Bool) -> some View {
            if !rows.isEmpty {
                CountedSectionHeader(
                    title,
                    count: counted ? rows.count : nil,
                    countLabel: counted ? TasksStrings.plural("tasks.requests.minePending", rows.count) : nil,
                    tone: .info
                )
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.medium)
                .padding(.bottom, Spacing.extraSmall)
                .tasksListRow()
                ForEach(rows) { item in
                    RequestCard(item: item, waiting: false) { actions.openOwn(item) }
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.extraSmall)
                        .tasksListRow()
                }
            }
        }

        private var loading: some View {
            SkeletonList(rows: 2)
                .padding(.top, Spacing.medium)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(TasksStrings.text("tasks.requests.loading")))
                .tasksListRow()
        }

        private var webFooter: some View {
            VStack(alignment: .leading, spacing: 0) {
                WaiveraButton(
                    TasksStrings.text("tasks.requests.openWeb"),
                    variant: .text,
                    systemImage: "arrow.up.right.square",
                    fillsWidth: true,
                    action: actions.openWeb
                )
                Text(TasksStrings.text("tasks.requests.webNote"))
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.extraSmall)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.small)
            .padding(.bottom, Spacing.large)
            .tasksListRow()
        }
    }
#endif
