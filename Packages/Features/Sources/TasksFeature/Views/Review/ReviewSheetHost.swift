#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    extension ReviewStep {
        /// Which sheet shows the step; a change of sheet closes one before the next opens.
        var sheet: String {
            switch self {
            case .lateReason: "lateReason"
            case .lateReview: "lateReview"
            case .confirmAll: "confirmAll"
            case .chooseScope: "chooseScope"
            case .drafts: "drafts"
            case .driveSection: "drive"
            case .closure: "closure"
            case .requirements: "requirements"
            case .related: "related"
            case .sendBack: "sendBack"
            }
        }
    }

    private struct ShownSheet: Identifiable, Equatable {
        let id: String
    }

    extension View {
        /// The review chain's sheets, one at a time. A step that needs another sheet waits for the
        /// open one to finish closing, so a quick chain never asks UIKit to present mid-dismissal.
        func taskReviewSheets(_ model: TaskReviewModel, today: CalendarDate?, onOpenWeb: @escaping () -> Void)
            -> some View
        {
            modifier(ReviewSheetHost(model: model, today: today, onOpenWeb: onOpenWeb))
        }
    }

    private struct ReviewSheetHost: ViewModifier {
        let model: TaskReviewModel
        let today: CalendarDate?
        let onOpenWeb: () -> Void

        @State private var shown: ShownSheet?
        @State private var closing = false

        func body(content: Content) -> some View {
            content
                .sheet(
                    item: Binding(
                        get: { shown },
                        set: { value in
                            guard value == nil, shown != nil else { return }
                            // Swiped away or Cancel: the chain stops (the model ignores it mid-send).
                            closing = true
                            shown = nil
                            model.dismiss()
                        }
                    ),
                    onDismiss: {
                        closing = false
                        sync()
                    }
                ) { _ in
                    ReviewSheetContent(model: model, today: today ?? model.today, onOpenWeb: onOpenWeb)
                }
                .onChange(of: model.state.step?.sheet, initial: true) { sync() }
        }

        private func sync() {
            let wanted = model.state.step.map { ShownSheet(id: $0.sheet) }
            guard !closing, shown != wanted else { return }
            if shown == nil {
                shown = wanted
            } else {
                closing = true
                shown = nil
            }
        }
    }

    /// The open step's sheet.
    private struct ReviewSheetContent: View {
        let model: TaskReviewModel
        let today: CalendarDate
        let onOpenWeb: () -> Void

        var body: some View {
            switch model.state.step {
            case .confirmAll(let stages, let submit):
                ConfirmationSheet(
                    title: TasksStrings.plural(
                        submit ? "tasks.review.submitAllTitle" : "tasks.review.allTitle",
                        stages
                    ),
                    message: TasksStrings.text("tasks.review.allMessage"),
                    confirmTitle: TasksStrings.text(submit ? "tasks.review.submitAll" : "tasks.review.allConfirm"),
                    cancelTitle: TasksStrings.text("tasks.review.goBack"),
                    isDestructive: false,
                    dismissesOnConfirm: false,
                    onConfirm: { model.confirmAll() }
                )
                .waiveraFittedSheetPresentation()
            case .chooseScope(let stages, let submit):
                ScopeSheet(stages: stages, submit: submit) { model.chooseScope(all: $0) }
                    .waiveraFittedSheetPresentation()
            case .drafts(let names):
                ConfirmationSheet(
                    title: TasksStrings.plural("tasks.review.draftsTitle", max(names.count, 1)),
                    message: Self.draftsMessage(names),
                    confirmTitle: TasksStrings.text("tasks.review.draftsConfirm"),
                    cancelTitle: TasksStrings.text("tasks.review.goBack"),
                    dismissesOnConfirm: false,
                    onConfirm: { model.discardDrafts() }
                )
                .waiveraFittedSheetPresentation()
            case .driveSection(let previous, let original):
                DriveSectionSheet(previous: previous, useOriginal: original, today: today, model: model)
            case .related(let blocked, let tasks, let saving):
                RelatedTasksSheet(blocked: blocked, tasks: tasks, isSaving: saving, model: model)
            case .closure(let form):
                ClosureSheet(form: form, today: today, model: model)
            case .requirements(let form):
                RequirementsSheet(
                    form: form,
                    action: model.state.running ?? .approve,
                    today: today,
                    model: model,
                    onOpenWeb: onOpenWeb
                )
            case .lateReason(let form):
                LateReasonSheet(form: form, today: today, model: model)
            case .lateReview(let check):
                LateReviewSheet(check: check, model: model)
            case .sendBack(let form):
                SendBackSheet(form: form, model: model)
            case nil:
                Palette.surface
            }
        }

        /// The device's own list wording ("A, B and C"), not a hard-coded comma.
        static func draftsMessage(_ names: [String]) -> String {
            guard !names.isEmpty else { return TasksStrings.text("tasks.review.draftsMessage") }
            let quoted = names.map { TasksStrings.format("tasks.review.quoted", $0) }
            let list = ListFormatter.localizedString(byJoining: quoted)
            return TasksStrings.plural("tasks.review.draftsNamed", names.count, list)
        }
    }
#endif
