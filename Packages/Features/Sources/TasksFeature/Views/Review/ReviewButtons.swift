#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct ReviewBarActions {
        var start: (ReviewAction) -> Void = { _ in }
        var reject: () -> Void = {}
    }

    /// The task's review buttons (Android `ReviewButtons`), from the server's capabilities only
    /// (web TaskPage): the assignee's Submit, or a reviewer's Approve and Reject. "All remaining &
    /// complete" is asked in a sheet after Approve or Submit, for those allowed it, so the bar stays
    /// two buttons. Submit and Approve wait for every required form, file and signature.
    struct ReviewButtons: View {
        let access: TaskReviewAccess
        let state: ReviewState
        let actions: ReviewBarActions
        /// A short screen (iPhone SE) takes the 48pt buttons so the bar stays out of the way.
        var compact = false

        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            VStack(spacing: compact ? Spacing.extraSmall : Spacing.small) {
                if access.canSubmit {
                    WaiveraButton(
                        TasksStrings.text("tasks.review.submit"),
                        size: buttonSize,
                        systemImage: "checkmark",
                        isLoading: loading(.submit),
                        loadingTitle: progress,
                        fillsWidth: true
                    ) { actions.start(.submit) }
                    .disabled(!access.ready || blocked(.submit))
                } else {
                    approveReject
                }
                if !access.ready, access.canSubmit || access.canApprove {
                    Text(TasksStrings.text("tasks.review.notReady"))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.warningText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        /// Behind a sheet that waits for an answer the button just stays disabled: nothing is sent yet.
        private var progress: String? {
            if state.step == nil { return TasksStrings.text("tasks.review.checking") }
            if state.stepSaving { return TasksStrings.text("tasks.review.sending") }
            return nil
        }

        private var buttonSize: WaiveraButtonSize { compact ? .regular : .large }

        /// "All" runs under the button that asked for it.
        private func loading(_ action: ReviewAction) -> Bool {
            (state.running == action || state.running == action.all) && progress != nil
        }

        /// Another action is working, or this one waits behind a sheet; a loading button stays live
        /// so it keeps its colour while its spinner shows.
        private func blocked(_ action: ReviewAction) -> Bool { state.busy && !loading(action) }

        @ViewBuilder private var approveReject: some View {
            if access.canApprove, access.canReject {
                if typeSize.isAccessibilitySize {
                    VStack(spacing: Spacing.small) {
                        approve
                        reject
                    }
                } else {
                    WeightedRow(weights: [1, 1.4], spacing: Spacing.small) {
                        reject
                        approve
                    }
                }
            } else if access.canApprove {
                approve
            } else if access.canReject {
                reject
            }
        }

        private var approve: some View {
            WaiveraButton(
                TasksStrings.text("tasks.review.approve"),
                size: buttonSize,
                systemImage: "checkmark",
                isLoading: loading(.approve),
                loadingTitle: progress,
                fillsWidth: true
            ) { actions.start(.approve) }
            .disabled(!access.ready || blocked(.approve))
        }

        private var reject: some View {
            WaiveraButton(
                TasksStrings.text("tasks.review.reject"),
                variant: .destructiveOutline,
                size: buttonSize,
                isLoading: state.rejecting && state.step == nil,
                loadingTitle: TasksStrings.text("tasks.review.checking"),
                fillsWidth: true,
                action: actions.reject
            )
            .disabled(state.busy && !(state.rejecting && state.step == nil))
        }
    }
#endif
