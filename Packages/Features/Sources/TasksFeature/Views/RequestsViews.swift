#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Requests list on its own screen, for an approval notification or link.
    public struct RequestsView: View {
        let onOpenTask: (_ taskID: Int) -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: RequestsModel?

        public init(onOpenTask: @escaping (_ taskID: Int) -> Void) {
            self.onOpenTask = onOpenTask
        }

        public var body: some View {
            Group {
                if let model {
                    RequestsScreen(model: model, onOpenTask: onOpenTask)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(TasksStrings.text("tasks.segment.requests"))
            .waiveraTopBar(TasksStrings.text("tasks.segment.requests"))
            .task {
                if model == nil, let data { model = RequestsModel(environment: data) }
            }
        }
    }

    /// Requests bound to its model: the review and confirm sheets and the web hand-off.
    struct RequestsScreen: View {
        let model: RequestsModel
        let onOpenTask: (Int) -> Void

        @Environment(\.openURL) private var openURL

        var body: some View {
            RequestsContent(
                state: model.state,
                actions: RequestsActions(
                    review: { item in
                        if let url = model.review(item) { openURL(url) }
                    },
                    openWeb: {
                        if let url = model.webURL() { openURL(url) }
                    },
                    retryWaiting: { model.retryWaiting() },
                    retryMine: { model.retryMine() }
                ),
                onRefresh: { [model] in await model.refresh() }
            )
            .sheet(
                isPresented: Binding(
                    get: { model.state.reviewing != nil },
                    set: { if !$0 { model.closeReview() } }
                )
            ) {
                if let item = model.state.reviewing {
                    ReviewSheet(
                        item: item,
                        onApprove: { model.ask(approve: true) },
                        onReject: { model.ask(approve: false) },
                        onOpenTask: item.request.taskId.map { id in
                            {
                                model.closeReview()
                                onOpenTask(id)
                            }
                        }
                    )
                    .waiveraSheetPresentation()
                    .sheet(
                        isPresented: Binding(
                            get: { model.state.confirming != nil },
                            set: { if !$0 { model.cancelConfirm() } }
                        )
                    ) {
                        if let decision = model.state.confirming {
                            let copy = decision.item.confirmation(approve: decision.approve)
                            ConfirmationSheet(
                                title: copy.title,
                                message: copy.message,
                                confirmTitle: TasksStrings.text(decision.approve ? "tasks.approve" : "tasks.reject"),
                                isDestructive: !decision.approve,
                                dismissesOnConfirm: false,
                                onConfirm: { model.confirm() }
                            )
                            .waiveraSheetPresentation()
                        }
                    }
                }
            }
            .tasksFeedback(model.feedback)
            .task { await model.run() }
        }
    }

    struct RequestsActions {
        var review: (RequestItem) -> Void = { _ in }
        var openWeb: () -> Void = {}
        var retryWaiting: () -> Void = {}
        var retryMine: () -> Void = {}
    }

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

    /// One request: its kind, the task, what changes and who asked when.
    struct RequestCard: View {
        let item: RequestItem
        let showsStatus: Bool
        let onOpen: () -> Void

        var body: some View {
            Button(action: onOpen) {
                HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                    IconTile(
                        systemImage: icon,
                        tone: tone,
                        size: ControlSize.fieldTile,
                        glyphSize: ControlSize.fieldTileGlyph
                    )
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        HStack(spacing: Spacing.small) {
                            Text(item.kindLabel)
                                .waiveraTextStyle(.labelMedium, weight: .bold)
                                .foregroundStyle(Palette.accent)
                            if showsStatus {
                                StatusBadge(item.statusLabel, tone: statusTone)
                            }
                        }
                        Text(item.request.taskTitle ?? item.request.typeName)
                            .waiveraTextStyle(.titleSmall, weight: .semibold)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                        if let change = item.change.text {
                            Text(change)
                                .waiveraTextStyle(.bodySmall, weight: .semibold)
                                .foregroundStyle(Palette.text)
                        }
                        Text(byLine)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(Spacing.medium)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.listCard))
                .overlay(RoundedRectangle(cornerRadius: Radius.listCard).stroke(Palette.border))
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .combine)
            .accessibilityHint(
                Text(
                    TasksStrings.text(
                        item.request.kind.reviewableHere ? "tasks.request.review" : "tasks.request.openWeb"
                    )
                )
            )
        }

        private var byLine: String {
            [item.request.requesterName.isEmpty ? nil : item.request.requesterName, item.asked?.text]
                .compactMap(\.self)
                .joined(separator: " · ")
        }

        private var icon: String {
            switch item.request.kind {
            case .moreTime: "calendar.badge.clock"
            case .delay: "clock.badge.exclamationmark"
            case .closure: "xmark.circle"
            case .other: "doc.text"
            }
        }

        private var tone: TileTone {
            switch item.request.kind {
            case .moreTime: .brand
            case .delay: .amber
            case .closure: .rose
            case .other: .neutral
            }
        }

        private var statusTone: BadgeTone {
            switch item.request.status {
            case .approved: .success
            case .rejected: .danger
            case .pending, .other: .warning
            }
        }
    }

    /// The facts of one request, with Approve and Reject; each is confirmed on its own sheet.
    struct ReviewSheet: View {
        let item: RequestItem
        let onApprove: () -> Void
        let onReject: () -> Void
        let onOpenTask: (() -> Void)?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(item.reviewTitle)
                        .waiveraTextStyle(.titleLarge, weight: .bold)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    if let asked = item.asked {
                        Text(TasksStrings.format("tasks.review.requested", asked.text))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    CardGroup {
                        fact(TasksStrings.text("tasks.review.task"), item.request.taskTitle)
                        fact(changeLabel, item.change.text)
                        fact(reasonLabel, item.request.reason)
                        fact(TasksStrings.text("tasks.review.note"), item.request.explanation)
                        if item.request.isTrainingTask {
                            fact(TasksStrings.text("tasks.review.training"), TasksStrings.text("tasks.yes"))
                        }
                    }
                    if let onOpenTask {
                        WaiveraButton(
                            TasksStrings.text("tasks.openTask"),
                            variant: .text,
                            systemImage: "arrow.right.circle",
                            action: onOpenTask
                        )
                    }
                    HStack(spacing: Spacing.mediumSmall) {
                        WaiveraButton(
                            TasksStrings.text("tasks.reject"),
                            variant: .destructiveOutline,
                            fillsWidth: true,
                            action: onReject
                        )
                        WaiveraButton(TasksStrings.text("tasks.approve"), fillsWidth: true, action: onApprove)
                    }
                }
                .padding(Spacing.gutter)
            }
            .background(Palette.surface)
        }

        private var changeLabel: String {
            switch item.request.kind {
            case .moreTime: TasksStrings.text("tasks.review.dueChange")
            case .delay: TasksStrings.text("tasks.review.delayWindow")
            default: TasksStrings.text("tasks.review.closure")
            }
        }

        private var reasonLabel: String {
            switch item.request.kind {
            case .moreTime: TasksStrings.text("tasks.review.reasonCode")
            case .delay: TasksStrings.text("tasks.review.delayReason")
            default: TasksStrings.text("tasks.review.closureReason")
            }
        }

        @ViewBuilder
        private func fact(_ label: String, _ value: String?) -> some View {
            if let value, !value.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(label)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                    Text(value)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.medium)
                .accessibilityElement(children: .combine)
            }
        }
    }

    #if DEBUG
        #Preview("Requests") {
            NavigationStack { RequestsView(onOpenTask: { _ in }) }.fakeDataEnvironment()
        }
        #Preview("Requests dark") {
            NavigationStack { RequestsView(onOpenTask: { _ in }) }.fakeDataEnvironment().preferredColorScheme(.dark)
        }
        #Preview("Requests AX5") {
            NavigationStack { RequestsView(onOpenTask: { _ in }) }.fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
