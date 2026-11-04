#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The stateless Requests list: waiting on you, then your own, then the web note.
    struct RequestsContent: View {
        let state: RequestsScreenState
        let actions: RequestsActions
        let onRefresh: @Sendable () async -> Void

        var body: some View {
            List {
                section(
                    title: TasksStrings.text("tasks.requests.waiting"),
                    items: state.waiting,
                    empty: TasksStrings.text("tasks.requests.noneWaiting"),
                    error: TasksStrings.text("tasks.requests.waitingError"),
                    retry: actions.retryWaiting,
                    reviewable: true
                )
                section(
                    title: TasksStrings.text("tasks.requests.mine"),
                    items: state.mine,
                    empty: TasksStrings.text("tasks.requests.noneMine"),
                    error: TasksStrings.text("tasks.requests.mineError"),
                    retry: actions.retryMine,
                    reviewable: false
                )
                VStack(alignment: .leading, spacing: Spacing.small) {
                    Text(TasksStrings.text("tasks.requests.webNote"))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                    WaiveraButton(
                        TasksStrings.text("tasks.requests.openWeb"),
                        variant: .text,
                        size: .compact,
                        systemImage: "arrow.up.right.square",
                        action: actions.openWeb
                    )
                }
                .padding(Spacing.gutter)
                .tasksListRow()
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
            .accessibilityIdentifier("requests.list")
        }

        @ViewBuilder
        private func section(
            title: String,
            items: Loadable<[RequestItem]>,
            empty: String,
            error: String,
            retry: @escaping () -> Void,
            reviewable: Bool
        ) -> some View {
            Text(title)
                .waiveraTextStyle(.labelLarge, weight: .bold)
                .foregroundStyle(Palette.text)
                .accessibilityAddTraits(.isHeader)
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.medium)
                .tasksListRow()
            switch items {
            case .loading:
                SkeletonList(rows: 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TasksStrings.text("tasks.requests.loading")))
                    .tasksListRow()
            case .failed:
                EmptyStateView.error(title: error, message: "", onRetry: retry).tasksListRow()
            case .ready(let list) where list.isEmpty:
                Text(empty)
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.textSecondary)
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.small)
                    .tasksListRow()
            case .ready(let list):
                ForEach(list) { item in
                    RequestCard(item: item, showsStatus: !reviewable) { actions.review(item) }
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.vertical, Spacing.extraSmall)
                        .tasksListRow()
                }
            }
        }
    }
#endif
