#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The stateless task screen, for the entry view, previews and snapshots.
    struct TaskDetailContent: View {
        let state: TaskDetailScreenState
        var uploads = TaskUploadsState()
        var review = ReviewState()
        let actions: TaskDetailActions
        let onRefresh: @Sendable () async -> Void

        @Environment(\.dynamicTypeSize) private var typeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        /// The whole screen's height (safe areas and the keyboard added back), so a short phone
        /// (iPhone SE, 667pt) gets a slimmer review bar and the bar never flips as the keyboard moves.
        @State private var screenHeight: CGFloat = 0

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
            .onGeometryChange(
                for: CGFloat.self,
                of: { $0.size.height + $0.safeAreaInsets.top + $0.safeAreaInsets.bottom },
                action: { screenHeight = $0 }
            )
        }

        /// Under this (iPhone SE and its kind; a mini is 812pt) the full-size bar takes a third of the screen.
        private static let shortScreenHeight: CGFloat = 700

        private var shortScreen: Bool { screenHeight > 0 && screenHeight < Self.shortScreenHeight }

        private func detail(_ task: TaskDetail) -> some View {
            ScrollViewReader { proxy in
                scroller(task) {
                    withAnimation(reduceMotion ? nil : .spring(duration: 0.45)) {
                        proxy.scrollTo(ActivitySection.latestID, anchor: .bottom)
                    }
                }
            }
        }

        private func scroller(_ task: TaskDetail, jump: @escaping () -> Void) -> some View {
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
                    TaskFacts(state: state, task: task, onOpenParticipant: actions.openParticipant)
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
                    RequiredFilesSection(
                        required: uploads.required,
                        canUpload: state.canUpload,
                        actions: actions.uploads
                    )
                    FilesSection(
                        files: state.files,
                        uploads: uploads.uploads,
                        canUpload: state.canUpload,
                        uploadActions: actions.uploads,
                        onOpen: actions.openFile,
                        onRetry: actions.retryFiles
                    )
                    ActivitySection(activity: state.activity, onRetry: actions.retryActivity, onJump: jump)
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
                VStack(spacing: shortScreen ? Spacing.extraSmall : Spacing.small) {
                    if let task = state.task, state.canLog, task.review.any {
                        ReviewButtons(
                            access: task.review,
                            state: review,
                            actions: actions.review,
                            compact: shortScreen
                        )
                        secondaryActions
                    } else if state.canLog {
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
                    if state.canAsk, state.task?.review.any != true {
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
                .padding(.vertical, shortScreen ? Spacing.small : Spacing.mediumSmall)
            }
            .background(Palette.background)
        }

        /// With review buttons on top, Log activity and Ask for a change step down to quiet text
        /// buttons side by side (stacked at large text), so the bar never grows past three rows.
        @ViewBuilder private var secondaryActions: some View {
            let log = WaiveraButton(
                TasksStrings.text("tasks.log.title"),
                variant: .text,
                systemImage: "plus",
                fillsWidth: true,
                action: actions.log
            )
            let ask = WaiveraButton(
                TasksStrings.text("tasks.ask.title"),
                variant: .text,
                fillsWidth: true,
                action: actions.ask
            )
            if !state.canAsk {
                log
            } else if typeSize.isAccessibilitySize {
                log
                ask
            } else {
                HStack(spacing: Spacing.small) {
                    log
                    ask
                }
            }
        }
    }
#endif
