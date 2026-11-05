#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// web `RejectTaskModal` (Android `SendBackSheet`): who fixes it, what to fix, and the
    /// reviewer's time. Returning a late reason asks only who and what to correct.
    struct SendBackSheet: View {
        let form: SendBackForm
        let model: TaskReviewModel

        var body: some View {
            ReviewSheetFrame(
                title: TasksStrings.text(
                    form.returnsLateReason ? "tasks.review.returnLateTitle" : "tasks.review.sendBackTitle"
                ),
                isSaving: form.isSaving
            ) {
                if form.failed { BannerView(.error, message: TasksStrings.text("tasks.review.sendBackFailed")) }
                sendTo
                ReviewTextArea(
                    label: TasksStrings.text(Self.feedbackKey(late: form.returnsLateReason)),
                    placeholder: TasksStrings.text(Self.feedbackKey(late: form.returnsLateReason) + "Placeholder"),
                    text: form.feedback,
                    error: feedbackError,
                    enabled: !form.isSaving
                ) { model.setFeedback($0) }
                // Returning a late reason records no review time, as on the web.
                if !form.returnsLateReason {
                    WaiveraTextField(
                        TasksStrings.text("tasks.review.minutes"),
                        text: Binding(get: { form.minutes }, set: { model.setMinutes($0) }),
                        placeholder: TasksStrings.text("tasks.review.minutesPlaceholder"),
                        error: form.minutesInvalid ? TasksStrings.text("tasks.review.minutesInvalid") : nil,
                        keyboard: .numberPad
                    )
                    .disabled(form.isSaving)
                }
            } bar: {
                WaiveraButton(
                    TasksStrings.text("tasks.review.sendBack"),
                    variant: .destructive,
                    size: .large,
                    isLoading: form.isSaving,
                    loadingTitle: TasksStrings.text("tasks.review.sending"),
                    fillsWidth: true
                ) { model.submitSendBack() }
                .disabled(form.noOptions || form.feedbackTooLong)
            }
        }

        @ViewBuilder private var sendTo: some View {
            switch form.options {
            case .loading:
                ReviewLabel(TasksStrings.text("tasks.review.sendTo"))
                SkeletonBlock(height: ControlSize.fieldHeight)
            case .failed:
                ReviewLabel(TasksStrings.text("tasks.review.sendTo"))
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.review.sendToError"),
                    message: "",
                    onRetry: { model.loadSendBackOptions() }
                )
            case .ready(let options) where options.isEmpty:
                BannerView(.warning, message: TasksStrings.text("tasks.review.noEarlierStep"))
            case .ready(let options):
                ReviewMenuField(
                    label: TasksStrings.text("tasks.review.sendTo"),
                    value: form.option.map(Self.label),
                    placeholder: TasksStrings.text("tasks.review.sendToPlaceholder"),
                    error: form.showErrors && form.optionMissing
                        ? TasksStrings.text("tasks.review.sendToRequired") : nil,
                    enabled: !form.isSaving
                ) {
                    ForEach(options) { option in
                        Button {
                            model.chooseSendBack(option.approvalId)
                        } label: {
                            if option.approvalId == form.approvalId {
                                Label(Self.label(option), systemImage: "checkmark")
                            } else {
                                Text(Self.label(option))
                            }
                        }
                    }
                }
            }
        }

        private var feedbackError: String? {
            if let over = ReviewTextArea.overLimit(form.feedback, limit: SendBackForm.maxFeedback) { return over }
            return form.showErrors && form.feedbackMissing ? TasksStrings.text("tasks.review.feedbackRequired") : nil
        }

        private static func feedbackKey(late: Bool) -> String {
            late ? "tasks.review.correction" : "tasks.review.feedback"
        }

        static func label(_ option: SendBackOption) -> String {
            guard let role = option.role else { return option.name }
            return TasksStrings.format("tasks.review.personRole", option.name, role)
        }
    }
#endif
