#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Status, due, about, type, assigned to and by on one lifted card (Android `DetailBody`),
    /// one row per fact that has a value, with inset hairlines between them.
    struct TaskFacts: View {
        let state: TaskDetailScreenState
        let task: TaskDetail

        var body: some View {
            SheetCardGroup {
                VStack(spacing: 0) {
                    FactRow(systemImage: "list.bullet.clipboard", label: TasksStrings.text("tasks.field.status")) {
                        StatusBadge(TaskFormat.stateLabel(task.state), tone: Self.tone(task.state, late: state.late))
                    }
                    InsetDivider()
                    FactRow(systemImage: "calendar", label: TasksStrings.text("tasks.field.due")) {
                        FactValue(
                            text: state.dueDate ?? TasksStrings.text("tasks.due.none"),
                            color: state.late ? Palette.dangerText : Palette.text
                        )
                    }
                    if let about = task.about {
                        InsetDivider()
                        FactRow(systemImage: "person", label: TasksStrings.text("tasks.field.about")) {
                            FactValue(text: about)
                        }
                    }
                    if let type = task.type {
                        InsetDivider()
                        FactRow(systemImage: "number", label: TasksStrings.text("tasks.field.type")) {
                            FactValue(text: type)
                        }
                    }
                    if let assignee = task.assigneeName {
                        InsetDivider()
                        FactRow(systemImage: "person.2", label: TasksStrings.text("tasks.field.assignedTo")) {
                            FactValue(text: assignee)
                        }
                    }
                    if let by = task.assignedBy {
                        InsetDivider()
                        FactRow(systemImage: "person.2", label: TasksStrings.text("tasks.field.assignedBy")) {
                            FactValue(text: by)
                        }
                    }
                }
                .padding(.vertical, Spacing.mediumSmall)
            }
        }

        /// The status badge's tone (Android `TaskFormat.tone`): finished green, late red, in progress
        /// violet, in review amber, otherwise neutral.
        static func tone(_ state: TaskState, late: Bool) -> BadgeTone {
            switch state {
            case .completed, .closed: return .success
            default: break
            }
            if late { return .danger }
            switch state {
            case .inProgress: return .accent
            case .inReview: return .warning
            default: return .neutral
            }
        }
    }
#endif
