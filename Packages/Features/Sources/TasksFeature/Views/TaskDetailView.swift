#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// One task: status and dates, who it is about, the pending request or active delay, the
    /// description and the activity, with Log activity and Ask for a change.
    public struct TaskDetailView: View {
        let taskID: Int
        let onOpenFile: (_ taskID: Int, _ attachmentID: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: TaskDetailModel?

        /// `onOpenFile` pushes the read-only file viewer for a file the phone can show.
        public init(taskID: Int, onOpenFile: @escaping (_ taskID: Int, _ attachmentID: Int) -> Void = { _, _ in }) {
            self.taskID = taskID
            self.onOpenFile = onOpenFile
        }

        public var body: some View {
            Group {
                if let model {
                    TaskDetailScreen(model: model, onOpenFile: onOpenFile)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(title)
            .waiveraTopBar(title, subtitle: model?.state.task?.key)
            .task {
                let current = model ?? data.map { TaskDetailModel(taskId: taskID, environment: $0) }
                if model == nil { model = current }
                await current?.run()
            }
        }

        private var title: String { model?.state.task?.title ?? TasksStrings.text("tasks.detail.title") }
    }

    private struct TaskDetailScreen: View {
        let model: TaskDetailModel
        let onOpenFile: (Int, Int) -> Void

        @Environment(\.openURL) private var openURL

        var body: some View {
            TaskDetailContent(
                state: model.state,
                actions: TaskDetailActions(
                    log: { model.startLog() },
                    ask: { model.startAsk() },
                    openWeb: {
                        if let url = model.webURL() { openURL(url) }
                    },
                    retry: { model.load() },
                    retryActivity: { model.loadActivity() },
                    openFile: { row in
                        switch model.open(file: row) {
                        case .viewer(let attachmentId): onOpenFile(model.taskId, attachmentId)
                        case .web(let url): openURL(url)
                        case nil: break
                        }
                    },
                    retryFiles: { model.loadFiles() }
                ),
                onRefresh: { [model] in await model.refresh() }
            )
            .sheet(
                isPresented: Binding(get: { model.state.log != nil }, set: { if !$0 { model.dismissLog() } })
            ) {
                if let form = model.state.log {
                    LogActivitySheet(form: form, zone: model.state.zone, today: model.state.today, model: model)
                        .waiveraSheetPresentation()
                        .interactiveDismissDisabled(form.isSaving)
                }
            }
            .sheet(
                isPresented: Binding(get: { model.state.ask != nil }, set: { if !$0 { model.dismissAsk() } })
            ) {
                if let form = model.state.ask {
                    AskChangeSheet(form: form, today: model.state.today, zone: model.state.zone, model: model)
                        .waiveraSheetPresentation()
                }
            }
            .tasksFeedback(model.feedback)
        }
    }

    struct TaskDetailActions {
        var log: () -> Void = {}
        var ask: () -> Void = {}
        var openWeb: () -> Void = {}
        var retry: () -> Void = {}
        var retryActivity: () -> Void = {}
        var openFile: (FileRow) -> Void = { _ in }
        var retryFiles: () -> Void = {}
    }

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

    /// Status, due, start, about, type, assigned to and by: one row per fact that has a value.
    private struct TaskFacts: View {
        let state: TaskDetailScreenState
        let task: TaskDetail

        var body: some View {
            CardGroup {
                FactRow(
                    systemImage: "flag",
                    label: TasksStrings.text("tasks.field.status"),
                    value: TaskFormat.stateLabel(task.state),
                    isLate: state.late
                )
                FactRow(
                    systemImage: "calendar",
                    label: TasksStrings.text("tasks.field.due"),
                    value: state.dueDate.map { _ in state.due.text } ?? TasksStrings.text("tasks.due.none"),
                    isLate: state.late
                )
                if let start = state.startDate {
                    FactRow(
                        systemImage: "calendar.badge.plus",
                        label: TasksStrings.text("tasks.field.start"),
                        value: start
                    )
                }
                if let about = task.about {
                    FactRow(systemImage: "person", label: TasksStrings.text("tasks.field.about"), value: about)
                }
                if let type = task.type {
                    FactRow(systemImage: "tag", label: TasksStrings.text("tasks.field.type"), value: type)
                }
                if let assignee = task.assigneeName {
                    FactRow(
                        systemImage: "person.crop.circle.badge.checkmark",
                        label: TasksStrings.text("tasks.field.assignedTo"),
                        value: assignee
                    )
                }
                if let by = task.assignedBy {
                    FactRow(
                        systemImage: "person.badge.plus",
                        label: TasksStrings.text("tasks.field.assignedBy"),
                        value: by
                    )
                }
            }
        }
    }

    struct FactRow: View {
        let systemImage: String
        let label: String
        let value: String
        var isLate = false

        var body: some View {
            HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                IconTile(
                    systemImage: systemImage,
                    tone: isLate ? .danger : .brand,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(label)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                    Text(value)
                        .waiveraTextStyle(.bodyLarge, weight: .semibold)
                        .foregroundStyle(isLate ? Palette.dangerText : Palette.text)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.medium)
            .accessibilityElement(children: .combine)
        }
    }

    /// A tinted note above the facts: a pending request or an active delay.
    struct NoteCard: View {
        let title: String
        let message: String
        let systemImage: String
        let tone: TileTone

        var body: some View {
            HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                IconTile(
                    systemImage: systemImage,
                    tone: tone,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(title)
                        .waiveraTextStyle(.titleSmall, weight: .bold)
                        .foregroundStyle(Palette.text)
                    Text(message)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Spacing.medium)
            .background(tone.containerColor, in: RoundedRectangle(cornerRadius: Radius.banner))
            .accessibilityElement(children: .combine)
        }
    }

    #if DEBUG
        #Preview("Task") {
            NavigationStack { TaskDetailView(taskID: 12) }.fakeDataEnvironment()
        }
        #Preview("Task dark") {
            NavigationStack { TaskDetailView(taskID: 14) }.fakeDataEnvironment().preferredColorScheme(.dark)
        }
        #Preview("Task AX5") {
            NavigationStack { TaskDetailView(taskID: 12) }.fakeDataEnvironment().dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
