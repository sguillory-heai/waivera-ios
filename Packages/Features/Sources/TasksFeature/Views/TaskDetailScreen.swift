#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct TaskDetailScreen: View {
        let model: TaskDetailModel
        let onOpenFile: (Int, Int) -> Void
        var onOpenTask: (Int) -> Void = { _ in }
        var onOpenParticipant: (Int) -> Void = { _ in }

        @Environment(\.openURL) private var openURL
        /// The file whose View tap waits for the actions sheet to finish closing.
        @State private var openingFile: FileRow?

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
                    openFile: { row in show(model.choose(file: row)) },
                    retryFiles: { model.loadFiles() },
                    uploads: uploadActions,
                    review: ReviewBarActions(
                        start: { model.startReview($0) },
                        reject: { model.review.startReject() }
                    ),
                    openParticipant: onOpenParticipant
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
            .sheet(
                // `item:` keeps the sheet's last content while it slides away. With an `if let`
                // body it went blank the moment it closed, lost its fitted height and jumped to
                // full height mid-dismissal before the viewer pushed.
                item: Binding(
                    get: { model.fileActions.sheet },
                    set: { if $0 == nil { model.fileActions.dismiss() } }
                ),
                // Pushing the viewer while the sheet is still sliding away lays the new page out
                // mid-dismissal (its top bar lands halfway down); open it once the sheet is gone.
                onDismiss: {
                    guard let row = openingFile else { return }
                    openingFile = nil
                    show(model.open(file: row))
                }
            ) { sheet in
                TaskFileActionsSheet(sheet: sheet, model: model.fileActions) {
                    openingFile = sheet.row
                    model.fileActions.dismiss()
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

        private func show(_ opening: TaskDetailModel.FileOpening?) {
            switch opening {
            case .viewer(let attachmentId): onOpenFile(model.taskId, attachmentId)
            case .web(let url): openURL(url)
            case nil: break
            }
        }
    }
#endif
