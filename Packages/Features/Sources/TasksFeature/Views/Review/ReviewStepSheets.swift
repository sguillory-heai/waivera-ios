#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// Where a reopened task's finished file goes: the Drive section it was filed in before, or
    /// this month's.
    struct DriveSectionSheet: View {
        let previous: CalendarDate
        let useOriginal: Bool
        let today: CalendarDate
        let model: TaskReviewModel

        var body: some View {
            ReviewSheetFrame(title: TasksStrings.text("tasks.review.driveTitle")) {
                ChoiceRow(
                    title: TasksStrings.text("tasks.review.driveOriginal"),
                    detail: TasksStrings.format("tasks.review.driveOriginalDetail", TaskFormat.monthYear(previous)),
                    selected: useOriginal
                ) { model.chooseDrive(original: true) }
                ChoiceRow(
                    title: TasksStrings.text("tasks.review.driveLatest"),
                    detail: TaskFormat.monthYear(today),
                    selected: !useOriginal
                ) { model.chooseDrive(original: false) }
            } bar: {
                WaiveraButton(TasksStrings.text("tasks.review.continue"), size: .large, fillsWidth: true) {
                    model.confirmDrive()
                }
            }
        }
    }

    /// Related tasks that hold this one up: a blocker must be finished first; a warning can be
    /// completed past.
    struct RelatedTasksSheet: View {
        let blocked: Bool
        let tasks: [RelatedTask]
        let isSaving: Bool
        let model: TaskReviewModel

        var body: some View {
            ReviewSheetFrame(
                title: TasksStrings.text(blocked ? "tasks.review.blockedTitle" : "tasks.review.warningTitle"),
                isSaving: isSaving
            ) {
                Text(TasksStrings.text(blocked ? "tasks.review.blockedMessage" : "tasks.review.warningMessage"))
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.textSecondary)
                SheetCardGroup {
                    ForEach(Array(tasks.enumerated()), id: \.offset) { index, task in
                        if index > 0 { InsetDivider() }
                        Button {
                            model.openRelated(task.id)
                        } label: {
                            FactRow(
                                systemImage: "checklist",
                                label: task.relationship
                                    ?? TasksStrings.text(
                                        blocked ? "tasks.review.blockedRow" : "tasks.review.warningRow"
                                    ),
                                tone: blocked ? .danger : .amber,
                                showsChevron: true
                            ) {
                                FactValue(text: task.title.isEmpty ? task.key : task.title)
                                FactNote(text: Self.note(task))
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.press(.card))
                        // A dependency the server sent without its task id has nothing to open.
                        .disabled(isSaving || task.id <= 0)
                    }
                }
            } bar: {
                if blocked {
                    WaiveraButton(TasksStrings.text("tasks.review.openRelated"), size: .large, fillsWidth: true) {
                        if let first = tasks.first(where: { $0.id > 0 }) { model.openRelated(first.id) }
                    }
                    .disabled(tasks.isEmpty)
                    WaiveraButton(TasksStrings.text("tasks.review.close"), variant: .secondary, size: .large) {
                        model.dismiss()
                    }
                } else {
                    WaiveraButton(
                        TasksStrings.text("tasks.review.completeAnyway"),
                        size: .large,
                        isLoading: isSaving,
                        loadingTitle: TasksStrings.text("tasks.review.sending"),
                        fillsWidth: true
                    ) { model.completeAnyway() }
                    WaiveraButton(TasksStrings.text("tasks.review.goBack"), variant: .secondary, size: .large) {
                        model.dismiss()
                    }
                    .disabled(isSaving)
                }
            }
        }

        private static func note(_ task: RelatedTask) -> String {
            let status = task.statusName.map { TaskFormat.stateLabel(TaskState(name: $0)) }
            return [task.key.isEmpty ? nil : task.key, status].compactMap(\.self).joined(separator: " · ")
        }
    }
#endif
