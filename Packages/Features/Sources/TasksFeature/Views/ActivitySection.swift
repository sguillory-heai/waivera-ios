#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The task's activity, oldest first so new work lands at the bottom. A long log gets "Jump to
    /// latest" on its header (Android `ActivitySection`); at accessibility sizes it takes its own row.
    struct ActivitySection: View {
        /// The newest entry's scroll anchor.
        static let latestID = "task.activity.latest"
        /// More entries than this and the header offers Jump to latest.
        static let jumpAfter = 5

        let activity: Loadable<[ActivityRow]>
        let onRetry: () -> Void
        var onJump: (() -> Void)?

        @Environment(\.dynamicTypeSize) private var typeSize

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                let count = activity.value?.count ?? 0
                let jumps = count > Self.jumpAfter && onJump != nil
                TaskSectionTitle(
                    TasksStrings.text("tasks.activity.title"),
                    count: count,
                    countLabel: TasksStrings.plural("tasks.activity.count", count)
                )
                // The link keeps its 48pt target, centred on the title and reaching past the row,
                // so the card stays close under the header (Android `SectionActionOverhang`).
                .overlay(alignment: .trailing) {
                    if jumps, !typeSize.isAccessibilitySize {
                        jumpButton
                            .padding(.trailing, Spacing.gutter)
                            .offset(y: (Spacing.mediumPlus - Spacing.small) / 2)
                    }
                }
                if jumps, typeSize.isAccessibilitySize {
                    jumpButton.padding(.horizontal, Spacing.gutter).padding(.bottom, Spacing.small)
                }
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
                                .id(index == rows.count - 1 ? Self.latestID : "task.activity.\(row.id)")
                        }
                    }
                }
                .padding(.horizontal, Spacing.gutter)
            }
        }

        private var jumpButton: some View {
            Button {
                onJump?()
            } label: {
                Text(TasksStrings.text("tasks.activity.jump"))
                    .waiveraTextStyle(.labelLarge, weight: .semibold)
                    .foregroundStyle(Palette.link)
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.compact))
            .fixedSize()
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
