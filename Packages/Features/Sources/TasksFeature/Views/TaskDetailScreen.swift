#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TaskDetailScreen: View {
        let model: TaskDetailModel
        let onOpenFile: (Int, Int) -> Void
        var onOpenTask: (Int) -> Void = { _ in }

        @Environment(\.openURL) private var openURL

        var body: some View {
            TaskDetailContent(
                state: model.state,
                uploads: model.uploads.state,
                review: model.review.state,
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
                    retryFiles: { model.loadFiles() },
                    uploads: uploadActions,
                    review: ReviewBarActions(
                        start: { model.startReview($0) },
                        reject: { model.review.startReject() }
                    )
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
                }
            }
            .sheet(
                isPresented: Binding(
                    get: { model.uploads.state.sheet != nil },
                    set: { if !$0 { model.uploads.closeSheet() } }
                )
            ) {
                if let sheet = model.uploads.state.sheet {
                    UploadSourceSheet(sheet: sheet, model: model.uploads)
                }
            }
            .taskReviewSheets(model.review, today: model.state.today) {
                if let url = model.webURL() { openURL(url) }
            }
            .tasksFeedback(model.feedback)
            .onAppear {
                model.onOpen = { [onOpenTask] effect in
                    if case .openTask(let id) = effect { onOpenTask(id) }
                }
            }
        }

        private var uploadActions: UploadActions {
            let uploads = model.uploads
            return UploadActions(
                uploadRequired: { uploads.startRequired($0) },
                openForm: {
                    if let url = model.webURL() { openURL(url) }
                },
                retryRequired: { uploads.loadRequired() },
                addFile: { uploads.startExtra(employeeTask: model.state.task?.isClientTask == false) },
                retryUpload: { uploads.retry($0) },
                dismissUpload: { uploads.dismiss($0) }
            )
        }
    }
#endif
