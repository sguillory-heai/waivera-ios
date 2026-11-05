#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// More time, delays, closures, reopening and required files: what changes, why, and the task.
    struct ReviewTaskRequest: View {
        let item: RequestItem
        let onOpenTask: (() -> Void)?

        var body: some View {
            SheetCardGroup {
                changeRow
                if let reason = item.request.reason, !reason.isEmpty {
                    InsetDivider()
                    FactRow(systemImage: "number", label: reasonLabel) { FactValue(text: reason) }
                }
                if let note = item.request.explanation, !note.isEmpty {
                    InsetDivider()
                    FactRow(systemImage: "text.bubble", label: TasksStrings.text("tasks.review.note")) {
                        ActivityNote(text: note)
                    }
                }
            }
            if let title = item.request.taskTitle {
                taskLink(title)
            }
        }

        @ViewBuilder
        private var changeRow: some View {
            switch item.change {
            case .dueMove(_, _, let later):
                FactRow(systemImage: "clock", label: TasksStrings.text("tasks.review.dueChange")) {
                    FactValue(text: item.change.text ?? "")
                    if let later {
                        FactNote(text: TasksStrings.plural("tasks.daysLater", later), color: Palette.warningText)
                    }
                }
            case .delayWindow:
                FactRow(
                    systemImage: "exclamationmark.triangle",
                    label: TasksStrings.text("tasks.review.delayWindow"),
                    tone: .amber
                ) {
                    FactValue(text: item.change.text ?? "")
                }
            case .closure:
                FactRow(systemImage: "archivebox", label: TasksStrings.text("tasks.review.closure")) {
                    FactValue(text: TasksStrings.text("tasks.change.closure"))
                }
            case .reopen:
                FactRow(systemImage: "arrow.clockwise", label: TasksStrings.text("tasks.review.closure")) {
                    FactValue(text: TasksStrings.text("tasks.change.reopen"))
                    FactNote(text: TasksStrings.text("tasks.review.reopenNote"))
                }
            case .removeFile:
                FactRow(systemImage: "paperclip", label: TasksStrings.text("tasks.review.closure")) {
                    FactValue(text: TasksStrings.text("tasks.change.removeFile"))
                    FactNote(text: TasksStrings.text("tasks.review.removeFileNote"))
                }
            default:
                FactRow(systemImage: "calendar", label: item.kindLabel) {
                    FactValue(text: item.request.typeName)
                }
            }
        }

        private var reasonLabel: String {
            switch item.request.kind {
            case .delay: TasksStrings.text("tasks.review.delayReason")
            case .closure: TasksStrings.text("tasks.review.closureReason")
            default: TasksStrings.text("tasks.review.reasonCode")
            }
        }

        @ViewBuilder
        private func taskLink(_ title: String) -> some View {
            let row = FactRow(
                systemImage: "checklist",
                label: TasksStrings.text("tasks.review.task"),
                showsChevron: onOpenTask != nil
            ) {
                FactValue(text: title)
                if item.due != .none { FactNote(text: item.due.text) }
                if item.request.isTrainingTask { FactNote(text: TasksStrings.text("tasks.review.training")) }
            }
            SheetCardGroup {
                if let onOpenTask {
                    Button(action: onOpenTask) {
                        row.contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.card))
                    .accessibilityHint(Text(TasksStrings.text("tasks.openTask")))
                } else {
                    row
                }
            }
        }
    }

    /// A quieter line under a fact's value.
    struct FactNote: View {
        let text: String
        var color: Color = Palette.textSecondary

        var body: some View {
            Text(text)
                .waiveraTextStyle(.bodySmall)
                .foregroundStyle(color)
        }
    }
#endif
