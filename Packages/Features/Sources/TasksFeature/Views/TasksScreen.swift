#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TasksScreen: View {
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
#endif
