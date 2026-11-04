#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The task's activity, oldest first so new work lands at the bottom.
    struct ActivitySection: View {
        let activity: Loadable<[ActivityRow]>
        let onRetry: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                let count = activity.value?.count ?? 0
                TaskSectionTitle(
                    TasksStrings.text("tasks.activity.title"),
                    count: count,
                    countLabel: TasksStrings.plural("tasks.activity.count", count)
                )
                SheetCardGroup {
                    switch activity {
                    case .loading:
                        SkeletonList(rows: 2).padding(Spacing.medium)
                    case .failed:
                        EmptyStateView.error(
                            title: TasksStrings.text("tasks.activity.error"),
                            message: "",
                            onRetry: onRetry
                        )
                    case .ready(let rows) where rows.isEmpty:
                        Text(TasksStrings.text("tasks.activity.empty"))
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.textSecondary)
                            .padding(Spacing.medium)
                    case .ready(let rows):
                        ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                            if index > 0 { InsetDivider(inset: Spacing.medium) }
                            ActivityItemView(row: row)
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
            }
        }
    }

    private struct ActivityPreview: View {
        var body: some View {
            let rows = [
                ActivityRow(
                    id: 1,
                    type: "Home visit",
                    moment: nil,
                    byMe: true,
                    author: "Alex Rivera",
                    description: "Jordan was in good spirits. Mom asked to move Thursday's visit to the afternoon. "
                        + "We went over the plan, the signed copy and the next steps for the school meeting.",
                    minutes: 60
                ),
                ActivityRow(
                    id: 2,
                    type: "Phone call with the family about the schedule change",
                    moment: nil,
                    byMe: false,
                    author: "Dana Cole",
                    description: "Confirmed.",
                    minutes: 15
                ),
            ]
            ScrollView { ActivitySection(activity: .ready(rows), onRetry: {}) }
                .background(Palette.background)
        }
    }

    #Preview("Light") { ActivityPreview() }
    #Preview("Dark") { ActivityPreview().preferredColorScheme(.dark) }
    #Preview("AX5") { ActivityPreview().dynamicTypeSize(.accessibility5) }
#endif
