#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Connects the model's lifecycle to SwiftUI: both observation tasks are owned (and
    /// cancelled) by the view, and "today" moves on when the app becomes active again.
    struct ScheduleModelView: View {
        let model: ScheduleModel
        let onOpenEvent: (String) -> Void

        @Environment(\.scenePhase) private var scenePhase

        var body: some View {
            ScheduleScreenView(
                state: model.state,
                actions: ScheduleActions(
                    selectView: { model.select(view: $0) },
                    selectDate: { model.select(date: $0) },
                    step: { model.step($0) },
                    goToToday: { model.goToToday() },
                    retry: { model.retry() },
                    retryMilestones: { model.retryMilestones() },
                    openEvent: onOpenEvent
                ),
                refresh: { [model] in await model.refresh() }
            )
            .task { await model.start() }
            .task(id: model.feedKey) { await model.observeFeed() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { model.resume() }
            }
        }
    }
#endif
