#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TaskDetailScreen: View {
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
#endif
