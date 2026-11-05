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
                        extras: ReviewExtras(
                            balance: model.state.balance,
                            training: model.state.training,
                            openingCertificate: model.state.openingCertificate
                        ),
                        actions: ReviewActions(
                            approve: { model.ask(approve: true) },
                            reject: { model.ask(approve: false) },
                            openTask: item.request.taskId.map { id in
                                {
                                    model.closeReview()
                                    onOpenTask(id)
                                }
                            },
                            retry: { model.retryDetails() },
                            openCertificate: { model.openCertificate() },
                            openWeb: {
                                if let url = model.webURL() { openURL(url) }
                            }
                        )
                    )
                    .waiveraSheetPresentation()
                    .sheet(
                        isPresented: Binding(
                            get: { model.state.confirming != nil },
                            set: { if !$0 { model.cancelConfirm() } }
                        )
                    ) {
                        if let decision = model.state.confirming {
                            confirmSheet(decision)
                        }
                    }
                    .sheet(
                        isPresented: Binding(
                            get: { model.state.certificate != nil },
                            set: { if !$0 { model.closeCertificate() } }
                        )
                    ) {
                        if let file = model.state.certificate {
                            CertificateSheet(file: file)
                        }
                    }
                }
            }
            .tasksFeedback(model.feedback)
            .task { await model.run() }
        }

        @ViewBuilder
        private func confirmSheet(_ decision: Decision) -> some View {
            let copy = decision.item.confirmation(approve: decision.approve)
            if decision.item.request.kind == .trainingCredit, let credit = model.state.training.value {
                TrainingDecisionSheet(
                    title: copy.title,
                    message: copy.message,
                    approve: decision.approve,
                    credit: credit,
                    reason: Binding(get: { model.state.reason }, set: { model.setReason($0) }),
                    canConfirm: model.state.canConfirm,
                    onConfirm: { model.confirm() }
                )
                .waiveraSheetPresentation()
            } else {
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
#endif
