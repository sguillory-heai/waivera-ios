#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TasksScreen: View {
        @Bindable var model: TasksModel
        let requests: RequestsModel
        let onOpenTask: (Int) -> Void
        var onOpenMyRequests: () -> Void = {}

        var body: some View {
            VStack(spacing: 0) {
                HeroSection {
                    HeroTopBar(title: TasksStrings.text("tasks.title"))
                } content: {
                    EmptyView()
                }
                segments
                if model.state.segment == .requests {
                    RequestsScreen(model: requests, onOpenTask: onOpenTask, onOpenMine: onOpenMyRequests)
                } else {
                    TasksListContent(
                        state: model.state,
                        query: Binding(get: { model.state.query }, set: { model.setQuery($0) }),
                        actions: TasksListActions(
                            open: onOpenTask,
                            setWindow: { model.setWindow($0) },
                            setAssignedToMe: { model.setAssignedToMe($0) },
                            setDelays: { model.setDelays($0) },
                            showMore: { model.showMore($0) },
                            showFewer: { model.showFewer($0) },
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
                options: model.state.segments.map { segment -> SegmentedChips<TasksSegment>.Option in
                    let count = segment == .requests ? model.state.waitingCount : 0
                    return SegmentedChips.Option(
                        segment,
                        title: title(segment),
                        count: count,
                        countLabel: TasksStrings.plural("tasks.segment.waiting", count)
                    )
                },
                selection: Binding(get: { model.state.segment }, set: { model.setSegment($0) })
            )
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.extraSmall)
        }

        private func title(_ segment: TasksSegment) -> String {
            switch segment {
            case .casework: TasksStrings.text("tasks.segment.casework")
            case .myWork: TasksStrings.text("tasks.segment.myWork")
            case .requests: TasksStrings.text("tasks.segment.requests")
            }
        }
    }
#endif
