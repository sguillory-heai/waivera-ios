#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Status, due, start, about, type, assigned to and by: one row per fact that has a value.
    struct TaskFacts: View {
        let state: TaskDetailScreenState
        let task: TaskDetail

        var body: some View {
            CardGroup {
                FactRow(
                    systemImage: "flag",
                    label: TasksStrings.text("tasks.field.status"),
                    value: TaskFormat.stateLabel(task.state),
                    isLate: state.late
                )
                FactRow(
                    systemImage: "calendar",
                    label: TasksStrings.text("tasks.field.due"),
                    value: state.dueDate.map { _ in state.due.text } ?? TasksStrings.text("tasks.due.none"),
                    isLate: state.late
                )
                if let start = state.startDate {
                    FactRow(
                        systemImage: "calendar.badge.plus",
                        label: TasksStrings.text("tasks.field.start"),
                        value: start
                    )
                }
                if let about = task.about {
                    FactRow(systemImage: "person", label: TasksStrings.text("tasks.field.about"), value: about)
                }
                if let type = task.type {
                    FactRow(systemImage: "tag", label: TasksStrings.text("tasks.field.type"), value: type)
                }
                if let assignee = task.assigneeName {
                    FactRow(
                        systemImage: "person.crop.circle.badge.checkmark",
                        label: TasksStrings.text("tasks.field.assignedTo"),
                        value: assignee
                    )
                }
                if let by = task.assignedBy {
                    FactRow(
                        systemImage: "person.badge.plus",
                        label: TasksStrings.text("tasks.field.assignedBy"),
                        value: by
                    )
                }
            }
        }
    }
#endif
