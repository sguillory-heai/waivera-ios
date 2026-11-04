#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The stateless task list, for the entry view, previews and snapshots.
    struct TasksListContent: View {
        let state: TasksScreenState
        @Binding var query: String
        let actions: TasksListActions
        let onRefresh: @Sendable () async -> Void

        @State private var choosingDelays = false

        var body: some View {
            List {
                controls.tasksListRow()
                if let meta = state.meta {
                    Text(meta)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.gutter + Spacing.extraSmall)
                        .padding(.vertical, Spacing.xxSmall)
                        .tasksListRow()
                }
                content
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 0)
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state.sections)
            .accessibilityIdentifier("tasks.list")
            .sheet(isPresented: $choosingDelays) {
                DelaysSheet(selected: state.delays) { filter in
                    choosingDelays = false
                    actions.setDelays(filter)
                }
                .waiveraSheetPresentation()
            }
        }

        private var controls: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                SearchField(
                    state.searchPlaceholder,
                    placeholder: state.searchPlaceholder,
                    query: $query,
                    identifier: "tasks.search"
                )
                .padding(.horizontal, Spacing.gutter)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.small) {
                        ForEach(TaskWindow.allCases, id: \.self) { window in
                            ChipView(windowTitle(window), isSelected: state.window == window) {
                                actions.setWindow(window)
                            }
                        }
                        if state.segment == .casework {
                            ChipView(
                                TasksStrings.text("tasks.assignedToMe"),
                                isSelected: state.assignedToMe,
                                systemImage: "person"
                            ) {
                                actions.setAssignedToMe(!state.assignedToMe)
                            }
                        }
                        if state.showsDelays {
                            ChipView(
                                DelaysSheet.chipTitle(state.delays),
                                isSelected: state.delays != .show,
                                systemImage: "clock"
                            ) {
                                choosingDelays = true
                            }
                            .accessibilityLabel(
                                Text(TasksStrings.format("tasks.delays.description", DelaysSheet.title(state.delays)))
                            )
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.vertical, Spacing.extraSmall)
                }
            }
            .padding(.vertical, Spacing.extraSmall)
        }

        @ViewBuilder private var content: some View {
            switch state.phase {
            case .loading:
                SkeletonList(rows: 6)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TasksStrings.text("tasks.loading")))
                    .tasksListRow()
            case .error:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.error.title"),
                    message: state.error?.userMessage ?? "",
                    onRetry: actions.retry
                )
                .tasksListRow()
            case .empty:
                EmptyStateView(
                    illustration: state.query.isEmpty ? .caughtUp : .search,
                    title: state.emptyTitle,
                    message: state.emptyMessage,
                    actionTitle: state.query.isEmpty ? nil : TasksStrings.text("tasks.clearSearch"),
                    action: state.query.isEmpty ? nil : { query = "" }
                )
                .tasksListRow()
            case .content:
                ForEach(state.sections) { section in
                    TaskGroupHeader(section: section)
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.top, Spacing.medium)
                        .padding(.bottom, Spacing.extraSmall)
                        .tasksListRow()
                    ForEach(section.rows) { row in
                        TaskCard(row: row) { actions.open(row.id) }
                            .padding(.horizontal, Spacing.gutter)
                            .padding(.vertical, Spacing.extraSmall)
                            .tasksListRow()
                            .onAppear {
                                if row.id == state.sections.last?.rows.last?.id { actions.loadMore() }
                            }
                    }
                }
                if state.isLoadingMore {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(Spacing.medium)
                        .accessibilityLabel(Text(TasksStrings.text("tasks.loadingMore")))
                        .tasksListRow()
                }
            }
        }

        private func windowTitle(_ window: TaskWindow) -> String {
            switch window {
            case .dueSoon: TasksStrings.text("tasks.window.dueSoon")
            case .overdue: TasksStrings.text("tasks.window.overdue")
            case .allOpen: TasksStrings.text("tasks.window.all")
            }
        }
    }
#endif
