#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The task's activity, oldest first so new work lands at the bottom.
    struct ActivitySection: View {
        let activity: Loadable<[ActivityRow]>
        let onRetry: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack {
                    SectionHeader(TasksStrings.text("tasks.activity.title"))
                    Spacer()
                    if let rows = activity.value, !rows.isEmpty {
                        Text(TasksStrings.plural("tasks.activity.count", rows.count))
                            .waiveraTextStyle(.labelMedium)
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                switch activity {
                case .loading:
                    SkeletonList(rows: 2)
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
                case .ready(let rows):
                    CardGroup {
                        ForEach(rows) { ActivityItemView(row: $0) }
                    }
                }
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
            ScrollView { ActivitySection(activity: .ready(rows), onRetry: {}).padding(Spacing.gutter) }
                .background(Palette.background)
        }
    }

    #Preview("Light") { ActivityPreview() }
    #Preview("Dark") { ActivityPreview().preferredColorScheme(.dark) }
    #Preview("AX5") { ActivityPreview().dynamicTypeSize(.accessibility5) }
#endif
