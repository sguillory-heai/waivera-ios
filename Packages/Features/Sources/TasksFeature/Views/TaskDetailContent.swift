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
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    if let pending = state.pending {
                        NoteCard(title: pending.title, message: pending.message, systemImage: "hourglass", tone: .amber)
                    }
                    if let delay = state.delay {
                        NoteCard(
                            title: delay.through.map { TasksStrings.format("tasks.row.delayedThrough", $0) }
                                ?? TasksStrings.text("tasks.row.delayed"),
                            message: [delay.reason, delay.explanation, TasksStrings.text("tasks.delay.note")]
                                .compactMap(\.self)
                                .joined(separator: "\n"),
                            systemImage: "clock.badge.exclamationmark",
                            tone: .amber
                        )
                    }
                    TaskFacts(state: state, task: task)
                    if let description = task.description {
                        SectionHeader(TasksStrings.text("tasks.detail.description"))
                        Text(description)
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.text)
                            .textSelection(.enabled)
                    }
                    FilesSection(files: state.files, onOpen: actions.openFile, onRetry: actions.retryFiles)
                    ActivitySection(activity: state.activity, onRetry: actions.retryActivity)
                    buttons
                }
                .padding(Spacing.gutter)
            }
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
        }

        @ViewBuilder private var buttons: some View {
            VStack(spacing: Spacing.small) {
                if state.canLog {
                    WaiveraButton(
                        TasksStrings.text("tasks.log.title"),
                        systemImage: "plus",
                        fillsWidth: true,
                        action: actions.log
                    )
                } else {
                    Text(TasksStrings.text("tasks.detail.finished"))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
                if state.canAsk {
                    WaiveraButton(
                        TasksStrings.text("tasks.ask.title"),
                        variant: .secondary,
                        systemImage: "arrow.triangle.2.circlepath",
                        fillsWidth: true,
                        action: actions.ask
                    )
                }
                WaiveraButton(
                    TasksStrings.text("tasks.openOnWeb"),
                    variant: .text,
                    systemImage: "arrow.up.right.square",
                    action: actions.openWeb
                )
            }
            .padding(.top, Spacing.small)
        }
    }
#endif
