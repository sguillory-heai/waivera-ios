#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

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
#endif
