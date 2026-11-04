#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    extension View {
        /// The screen's toast at the bottom: silent, announced to VoiceOver, gone after a few seconds.
        func tasksFeedback(_ feedback: TasksFeedback, onRetry: @escaping (TasksRetry) -> Void = { _ in }) -> some View {
            modifier(TasksFeedbackModifier(feedback: feedback, onRetry: onRetry))
        }
    }

    private struct TasksFeedbackModifier: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
        let feedback: TasksFeedback
        let onRetry: (TasksRetry) -> Void

        func body(content: Content) -> some View {
            content
                .overlay(alignment: .bottom) {
                    if let toast = feedback.toast {
                        SnackbarView(
                            message: toast.message,
                            actionTitle: toast.retry == nil ? nil : TasksStrings.text("tasks.tryAgain"),
                            actionIdentifier: "tasks.toast.retry",
                            action: toast.retry.map { retry in
                                {
                                    feedback.dismiss(toast.id)
                                    onRetry(retry)
                                }
                            }
                        )
                        .padding(Spacing.medium)
                        .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                        .task(id: toast.id) {
                            AccessibilityNotification.Announcement(toast.message).post()
                            let lifetime = voiceOver ? FeedbackTiming.undoToastAccessible : FeedbackTiming.undoToast
                            try? await Task.sleep(for: .seconds(lifetime))
                            guard !Task.isCancelled else { return }
                            feedback.dismiss(toast.id)
                        }
                    }
                }
                .waiveraAnimation(.layout, value: feedback.toast)
        }
    }
#endif
