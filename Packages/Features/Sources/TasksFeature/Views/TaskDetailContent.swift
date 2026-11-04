#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The stateless task screen, for the entry view, previews and snapshots.
    struct TaskDetailContent: View {
        let state: TaskDetailScreenState
        let actions: TaskDetailActions
        let onRefresh: @Sendable () async -> Void

        var body: some View {
            LoadingContent(isLoading: state.phase == .loading) {
                if state.phase == .error {
                    EmptyStateView.error(
                        title: TasksStrings.text("tasks.detail.error.title"),
                        message: state.error?.userMessage ?? "",
                        onRetry: actions.retry
                    )
                    .frame(maxHeight: .infinity)
                } else if let task = state.task {
                    detail(task)
                }
            } skeleton: {
                SkeletonList(rows: 5)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TasksStrings.text("tasks.detail.loading")))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background)
        }

        private func detail(_ task: TaskDetail) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let pending = state.pending {
                        NoteCard(title: pending.title, message: pending.message, systemImage: "hourglass", tone: .amber)
                            .padding(.horizontal, Spacing.gutter)
                            .padding(.top, Spacing.small)
                            .padding(.bottom, Spacing.extraSmall)
                    }
                    if let delay = state.delay {
                        NoteCard(
                            title: delay.through.map { TasksStrings.format("tasks.row.delayedThrough", $0) }
                                ?? TasksStrings.text("tasks.row.delayed"),
                            message: [delay.reason, delay.explanation, TasksStrings.text("tasks.delay.note")]
                                .compactMap(\.self)
                                .joined(separator: "\n"),
                            systemImage: "clock",
                            tone: .brand
                        )
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.top, Spacing.small)
                        .padding(.bottom, Spacing.extraSmall)
                    }
                    TaskSectionTitle(
                        TasksStrings.text("tasks.detail.section"),
                        first: state.pending == nil && state.delay == nil
                    )
                    TaskFacts(state: state, task: task)
                        .padding(.horizontal, Spacing.gutter)
                    if let description = task.description, !description.isEmpty {
                        TaskSectionTitle(TasksStrings.text("tasks.detail.description"))
                        SheetCardGroup {
                            Text(description)
                                .waiveraTextStyle(.bodyMedium)
                                .foregroundStyle(Palette.text)
                                .textSelection(.enabled)
                                .padding(Spacing.medium)
                        }
                        .padding(.horizontal, Spacing.gutter)
                    }
                    FilesSection(files: state.files, onOpen: actions.openFile, onRetry: actions.retryFiles)
                    ActivitySection(activity: state.activity, onRetry: actions.retryActivity)
                }
                .padding(.bottom, Spacing.large)
            }
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
            .safeAreaInset(edge: .bottom, spacing: 0) { actionBar }
        }

        /// Log activity pinned in thumb reach, as Android's bottom action bar; Ask for a change
        /// under it while one can be asked.
        private var actionBar: some View {
            VStack(spacing: 0) {
                Rectangle().fill(Palette.border).frame(height: Spacing.hairline)
                VStack(spacing: Spacing.small) {
                    if state.canLog {
                        WaiveraButton(
                            TasksStrings.text("tasks.log.title"),
                            size: .large,
                            systemImage: "plus",
                            fillsWidth: true,
                            action: actions.log
                        )
                    } else {
                        Text(TasksStrings.text("tasks.detail.finished"))
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if state.canAsk {
                        WaiveraButton(
                            TasksStrings.text("tasks.ask.title"),
                            variant: .text,
                            size: .large,
                            fillsWidth: true,
                            action: actions.ask
                        )
                        .transition(.opacity)
                    }
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.mediumSmall)
            }
            .background(Palette.background)
        }
    }
#endif
