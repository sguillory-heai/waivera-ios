#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The facts of one request, with Approve and Reject; each is confirmed on its own sheet.
    struct ReviewSheet: View {
        let item: RequestItem
        let onApprove: () -> Void
        let onReject: () -> Void
        let onOpenTask: (() -> Void)?

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    Text(item.reviewTitle)
                        .waiveraTextStyle(.titleLarge, weight: .bold)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    if let asked = item.asked {
                        Text(TasksStrings.format("tasks.review.requested", asked.text))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    CardGroup {
                        fact(TasksStrings.text("tasks.review.task"), item.request.taskTitle)
                        fact(changeLabel, item.change.text)
                        fact(reasonLabel, item.request.reason)
                        fact(TasksStrings.text("tasks.review.note"), item.request.explanation)
                        if item.request.isTrainingTask {
                            fact(TasksStrings.text("tasks.review.training"), TasksStrings.text("tasks.yes"))
                        }
                    }
                    if let onOpenTask {
                        WaiveraButton(
                            TasksStrings.text("tasks.openTask"),
                            variant: .text,
                            systemImage: "arrow.right.circle",
                            action: onOpenTask
                        )
                    }
                    HStack(spacing: Spacing.mediumSmall) {
                        WaiveraButton(
                            TasksStrings.text("tasks.reject"),
                            variant: .destructiveOutline,
                            fillsWidth: true,
                            action: onReject
                        )
                        WaiveraButton(TasksStrings.text("tasks.approve"), fillsWidth: true, action: onApprove)
                    }
                }
                .padding(Spacing.gutter)
            }
            .background(Palette.surface)
        }

        private var changeLabel: String {
            switch item.request.kind {
            case .moreTime: TasksStrings.text("tasks.review.dueChange")
            case .delay: TasksStrings.text("tasks.review.delayWindow")
            default: TasksStrings.text("tasks.review.closure")
            }
        }

        private var reasonLabel: String {
            switch item.request.kind {
            case .moreTime: TasksStrings.text("tasks.review.reasonCode")
            case .delay: TasksStrings.text("tasks.review.delayReason")
            default: TasksStrings.text("tasks.review.closureReason")
            }
        }

        @ViewBuilder
        private func fact(_ label: String, _ value: String?) -> some View {
            if let value, !value.isEmpty {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(label)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                    Text(value)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.text)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Spacing.medium)
                .accessibilityElement(children: .combine)
            }
        }
    }
#endif
