#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Tasks tab root: Casework, My work and (for people the web shows Admin Requests to)
    /// Requests, under the hero bar. Casework and My work list open tasks by due group with a
    /// window, search, Assigned to me and the Delays choice; Requests reviews change requests.
    public struct TasksView: View {
        let onOpenTask: (_ taskID: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: TasksModel?
        @State private var requests: RequestsModel?

        public init(onOpenTask: @escaping (_ taskID: Int) -> Void) {
            self.onOpenTask = onOpenTask
        }

        public var body: some View {
            ZStack {
                Palette.background.ignoresSafeArea()
                if let model, let requests {
                    TasksScreen(model: model, requests: requests, onOpenTask: onOpenTask)
                }
            }
            .navigationTitle(TasksStrings.text("tasks.title"))
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if model == nil, let data {
                    model = TasksModel(environment: data)
                    requests = RequestsModel(environment: data)
                }
                await model?.run()
            }
        }
    }

    private struct TasksScreen: View {
        @Bindable var model: TasksModel
        let requests: RequestsModel
        let onOpenTask: (Int) -> Void

        var body: some View {
            VStack(spacing: 0) {
                HeroSection {
                    HeroTopBar(title: TasksStrings.text("tasks.title"))
                } content: {
                    EmptyView()
                }
                segments
                if model.state.segment == .requests {
                    RequestsScreen(model: requests, onOpenTask: onOpenTask)
                } else {
                    TasksListContent(
                        state: model.state,
                        query: Binding(get: { model.state.query }, set: { model.setQuery($0) }),
                        actions: TasksListActions(
                            open: onOpenTask,
                            setWindow: { model.setWindow($0) },
                            setAssignedToMe: { model.setAssignedToMe($0) },
                            setDelays: { model.setDelays($0) },
                            loadMore: { model.loadMore() },
                            retry: { model.retry() }
                        ),
                        onRefresh: { [model] in await model.refresh() }
                    )
                    .tasksFeedback(model.feedback, onRetry: { _ in model.retry() })
                }
            }
            .background(Palette.background)
        }

        private var segments: some View {
            SegmentedControl(
                options: model.state.segments.map { segment in
                    SegmentedChips.Option(segment, title: title(segment))
                },
                selection: Binding(get: { model.state.segment }, set: { model.setSegment($0) })
            )
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.small)
        }

        private func title(_ segment: TasksSegment) -> String {
            switch segment {
            case .casework: TasksStrings.text("tasks.segment.casework")
            case .myWork: TasksStrings.text("tasks.segment.myWork")
            case .requests:
                model.state.waitingCount > 0
                    ? TasksStrings.format("tasks.segment.requestsCount", String(model.state.waitingCount))
                    : TasksStrings.text("tasks.segment.requests")
            }
        }
    }

    struct TasksListActions {
        var open: (Int) -> Void = { _ in }
        var setWindow: (TaskWindow) -> Void = { _ in }
        var setAssignedToMe: (Bool) -> Void = { _ in }
        var setDelays: (DelayFilter) -> Void = { _ in }
        var loadMore: () -> Void = {}
        var retry: () -> Void = {}
    }

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
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .padding(.horizontal, Spacing.gutter)
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
            VStack(alignment: .leading, spacing: Spacing.small) {
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
                }
            }
            .padding(.vertical, Spacing.small)
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

    extension View {
        func tasksListRow() -> some View {
            listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }

    #if DEBUG
        #Preview("Light") {
            NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment().preferredColorScheme(.dark)
        }
        #Preview("AX5") {
            NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("Empty and failing") {
            TabView {
                NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment(.empty)
                    .tabItem { Text(verbatim: "empty") }
                NavigationStack { TasksView(onOpenTask: { _ in }) }.fakeDataEnvironment(.failing)
                    .tabItem { Text(verbatim: "failing") }
            }
        }
    #endif
#endif
