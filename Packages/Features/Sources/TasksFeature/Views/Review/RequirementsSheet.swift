#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// The stage's own questions, such as new plan dates (web `WorkflowApprovalRequirementsModal`).
    struct RequirementsSheet: View {
        let form: RequirementsForm
        let action: ReviewAction
        let today: CalendarDate
        let model: TaskReviewModel
        let onOpenWeb: () -> Void

        var body: some View {
            ReviewSheetFrame(title: TasksStrings.text("tasks.review.requirementsTitle"), isSaving: form.isSaving) {
                if let banner { BannerView(banner.kind, message: banner.message) }
                ForEach(form.requirements, id: \.actionId) { requirement in
                    block(requirement)
                }
            } bar: {
                if form.supported {
                    WaiveraButton(
                        buttonTitle,
                        size: .large,
                        systemImage: "checkmark",
                        isLoading: form.isSaving,
                        loadingTitle: TasksStrings.text("tasks.review.sending"),
                        fillsWidth: true
                    ) { model.submitRequirements() }
                } else {
                    WaiveraButton(
                        TasksStrings.text("tasks.review.openWeb"),
                        variant: .secondary,
                        size: .large,
                        systemImage: "arrow.up.right.square"
                    ) {
                        model.dismiss()
                        onOpenWeb()
                    }
                }
            }
        }

        private var banner: (kind: BannerKind, message: String)? {
            if form.failed { return (.error, TasksStrings.text("tasks.review.requirementsFailed")) }
            if form.changed { return (.warning, TasksStrings.text("tasks.review.requirementsChanged")) }
            if !form.supported { return (.info, TasksStrings.text("tasks.review.requirementsWeb")) }
            if form.confirmWarnings, form.hasWarnings {
                return (.warning, TasksStrings.text("tasks.review.requirementsWarnings"))
            }
            return nil
        }

        private var buttonTitle: String {
            if form.confirmWarnings, form.hasWarnings { return TasksStrings.text("tasks.review.requirementsAnyway") }
            return TasksStrings.text(action.submits ? "tasks.review.submit" : "tasks.review.approve")
        }

        @ViewBuilder
        private func block(_ requirement: StageRequirement) -> some View {
            if !requirement.title.isEmpty || requirement.description != nil {
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    if !requirement.title.isEmpty {
                        Text(requirement.title).waiveraTextStyle(.titleSmall).foregroundStyle(Palette.text)
                    }
                    if let description = requirement.description {
                        Text(description).waiveraTextStyle(.bodyMedium).foregroundStyle(Palette.textSecondary)
                    }
                }
            }
            let values = form.values[requirement.actionId] ?? [:]
            ForEach(requirement.fields.filter { $0.type != .unsupported }, id: \.key) { field in
                RequirementInput(
                    field: field,
                    value: values[field.key] ?? "",
                    error: form.errors[requirement.actionId]?[field.key],
                    warning: form.warnings[requirement.actionId]?[field.key],
                    enabled: !form.isSaving,
                    today: today
                ) { model.setRequirement(actionId: requirement.actionId, key: field.key, value: $0) }
            }
        }
    }

    /// One field of a requirement, with its error or warning under it.
    private struct RequirementInput: View {
        let field: RequirementField
        let value: String
        let error: RequirementIssue?
        let warning: RequirementIssue?
        let enabled: Bool
        let today: CalendarDate
        let onValue: (String) -> Void

        var body: some View {
            let errorText = error.map { RequirementText.issue($0, label: field.label) }
            let warningText = warning.map { RequirementText.issue($0, label: field.label) }
            switch field.type {
            case .date:
                ReviewDateField(
                    label: field.label,
                    value: RequirementChecks.date(value),
                    raw: value,
                    today: today,
                    error: errorText,
                    warning: warningText,
                    enabled: enabled
                ) { onValue($0.isoString) }
            case .longText:
                ReviewTextArea(
                    label: field.label,
                    placeholder: field.label,
                    text: value,
                    error: errorText,
                    enabled: enabled,
                    onChange: onValue
                )
                if errorText == nil, let warningText { ReviewNote(text: warningText, tone: .warning) }
            default:
                WaiveraTextField(
                    field.label,
                    text: Binding(get: { value }, set: onValue),
                    placeholder: field.label,
                    error: errorText,
                    keyboard: field.type == .number ? .numberPad : .default
                )
                .disabled(!enabled)
                if errorText == nil, let warningText { ReviewNote(text: warningText, tone: .warning) }
            }
        }
    }

    /// The wording of a requirement's field problems.
    enum RequirementText {
        static func issue(_ issue: RequirementIssue, label: String) -> String {
            switch issue.kind {
            case .required: TasksStrings.format("tasks.review.issueRequired", label)
            case .invalidDate: TasksStrings.text("tasks.review.issueInvalid")
            case .endBeforeStart: TasksStrings.text("tasks.review.issueEndBeforeStart")
            case .overAYearAgo: TasksStrings.text("tasks.review.issueYearAgo")
            case .expectedStart:
                TasksStrings.format("tasks.review.issueExpectedStart", issue.date.map(TaskFormat.fullDate) ?? "")
            case .expectedEnd:
                TasksStrings.format("tasks.review.issueExpectedEnd", issue.date.map(TaskFormat.fullDate) ?? "")
            }
        }
    }
#endif
