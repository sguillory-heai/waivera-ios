#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct ParticipantActions {
        var retry: () -> Void = {}
        var retryTasks: () -> Void = {}
        var openTask: (Int) -> Void = { _ in }
        var contact: (URL) -> Void = { _ in }
    }

    /// The stateless participant screen, for the entry view and previews.
    struct ParticipantContent: View {
        let state: ParticipantScreenState
        let actions: ParticipantActions

        var body: some View {
            LoadingContent(isLoading: state.phase == .loading) {
                switch state.phase {
                case .forbidden:
                    EmptyStateView(
                        systemImage: "lock",
                        title: TasksStrings.text("tasks.participant.forbiddenTitle"),
                        message: TasksStrings.text("tasks.participant.forbidden")
                    )
                    .padding(.top, Spacing.large)
                    .frame(maxHeight: .infinity, alignment: .top)
                default:
                    if let profile = state.profile {
                        content(profile)
                    } else {
                        EmptyStateView.error(
                            title: TasksStrings.text("tasks.participant.errorTitle"),
                            message: TasksStrings.text("tasks.participant.error"),
                            onRetry: actions.retry
                        )
                        .padding(.top, Spacing.large)
                        .frame(maxHeight: .infinity, alignment: .top)
                    }
                }
            } skeleton: {
                SkeletonList(rows: 5)
                    .frame(maxHeight: .infinity, alignment: .top)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TasksStrings.text("tasks.detail.loading")))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Palette.background)
        }

        private func content(_ profile: ParticipantProfile) -> some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    ParticipantIdentity(profile: profile)
                    if profile.mobile != nil || profile.email != nil {
                        TaskSectionTitle(TasksStrings.text("tasks.participant.contact"))
                        ParticipantContactCard(profile: profile, onContact: actions.contact)
                            .padding(.horizontal, Spacing.gutter)
                    }
                    TaskSectionTitle(TasksStrings.text("tasks.participant.planSection"))
                    ParticipantPlanCard(profile: profile, plan: state.plan)
                        .padding(.horizontal, Spacing.gutter)
                    TaskSectionTitle(TasksStrings.text("tasks.participant.details"))
                    ParticipantDetailsCard(profile: profile)
                        .padding(.horizontal, Spacing.gutter)
                    openTasks
                }
                .padding(.bottom, Spacing.large)
            }
            .waiveraAnimation(.layout, value: state)
        }

        @ViewBuilder private var openTasks: some View {
            let count = state.tasks.value?.count ?? 0
            TaskSectionTitle(
                TasksStrings.text("tasks.participant.tasks"),
                count: count > 0 ? count : nil,
                countLabel: TasksStrings.plural("tasks.participant.tasksCount", count),
                // Red while any of them is late, as on Android.
                tone: state.overdue > 0 ? .attention : .info
            )
            switch state.tasks {
            case .loading:
                SkeletonList(rows: 2)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TasksStrings.text("tasks.detail.loading")))
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.participant.tasksError"),
                    message: "",
                    onRetry: actions.retryTasks
                )
                .padding(.horizontal, Spacing.gutter)
            case .ready(let rows) where rows.isEmpty:
                EmptyStateView(
                    illustration: .caughtUp,
                    title: TasksStrings.text("tasks.participant.noTasksTitle"),
                    message: TasksStrings.text("tasks.participant.noTasks"),
                    dense: true
                )
            case .ready(let rows):
                VStack(spacing: Spacing.mediumSmall) {
                    ForEach(rows) { row in
                        TaskCard(row: row) { actions.openTask(row.id) }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
            }
        }
    }
#endif
