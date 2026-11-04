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

    struct ActivityItemView: View {
        let row: ActivityRow

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text([row.type, TaskFormat.duration(row.minutes)].filter { !$0.isEmpty }.joined(separator: " · "))
                    .waiveraTextStyle(.titleSmall, weight: .semibold)
                    .foregroundStyle(Palette.text)
                Text(byLine)
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                if let description = row.description {
                    Text(description)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.text)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Spacing.medium)
            .accessibilityElement(children: .combine)
        }

        private var byLine: String {
            let who = row.byMe ? TasksStrings.text("tasks.activity.byYou") : row.author
            return [row.moment?.text, who].compactMap(\.self).joined(separator: " · ")
        }
    }
#endif
