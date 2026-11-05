#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    private struct OpenEvidence: Identifiable { let id: Int }

    /// A reviewer's look at the late reason (Android `LateReviewSheet`): agree, correct it, or send
    /// the task back.
    struct LateReviewSheet: View {
        let check: LateCheck
        let model: TaskReviewModel

        @Environment(\.dynamicTypeSize) private var typeSize
        @State private var openFile: OpenEvidence?

        var body: some View {
            ReviewSheetFrame(title: TasksStrings.text("tasks.late.reviewTitle"), isSaving: check.isSaving) {
                if check.failed { BannerView(.error, message: TasksStrings.text("tasks.late.reviewFailed")) }
                if let justification = check.context.justification { facts(justification) }
                if !check.context.reviews.isEmpty { earlier }
                ReviewTextArea(
                    label: TasksStrings.text("tasks.late.note"),
                    placeholder: TasksStrings.text("tasks.late.notePlaceholder"),
                    text: check.note,
                    error: ReviewTextArea.overLimit(check.note, limit: LateCheck.maxNote),
                    enabled: !check.isSaving
                ) { model.setLateNote($0) }
            } bar: {
                bar
            }
            // The file opens over the review, so the chain is still there when it closes.
            .sheet(item: $openFile) { file in
                NavigationStack { TaskFileView(taskID: model.taskId, attachmentID: file.id) }
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }

        @ViewBuilder private var bar: some View {
            WaiveraButton(
                TasksStrings.text("tasks.late.agree"),
                size: .large,
                systemImage: "checkmark",
                isLoading: check.isSaving,
                loadingTitle: TasksStrings.text("tasks.review.sending"),
                fillsWidth: true
            ) { model.agreeLate() }
            // Side by side, the two labels wrap unevenly at large text; stacked they stay one line each.
            if typeSize.isAccessibilitySize {
                edit
                sendBack
            } else {
                HStack(spacing: Spacing.small) {
                    edit
                    sendBack
                }
            }
        }

        private var edit: some View {
            WaiveraButton(TasksStrings.text("tasks.late.edit"), variant: .secondary, size: .large, fillsWidth: true) {
                model.editLate()
            }
            .disabled(check.isSaving)
        }

        private var sendBack: some View {
            WaiveraButton(
                TasksStrings.text("tasks.review.sendBack"),
                variant: .destructiveOutline,
                size: .large,
                fillsWidth: true
            ) { model.returnLate() }
            .disabled(check.isSaving)
        }

        private func facts(_ justification: LateJustification) -> some View {
            SheetCardGroup {
                if let reason = justification.reasonName {
                    FactRow(systemImage: "number", label: TasksStrings.text("tasks.late.reason")) {
                        FactValue(text: reason)
                    }
                    InsetDivider()
                }
                FactRow(
                    systemImage: "text.bubble",
                    label: justification.submittedBy.map { TasksStrings.format("tasks.late.wrote", $0) }
                        ?? TasksStrings.text("tasks.late.explanationRow")
                ) {
                    ActivityNote(text: justification.explanation)
                }
                if let evidence = justification.evidenceId {
                    InsetDivider()
                    Button {
                        openFile = OpenEvidence(id: evidence)
                    } label: {
                        FactRow(systemImage: "paperclip", label: TasksStrings.text("tasks.late.evidence"), showsChevron: true) {
                            FactValue(text: TasksStrings.text("tasks.late.openFile"), color: Palette.accent)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.card))
                }
                if justification.delayId != nil {
                    InsetDivider()
                    FactRow(systemImage: "clock", label: TasksStrings.text("tasks.late.linkedDelay")) {
                        FactValue(text: TasksStrings.text("tasks.row.delayed"))
                    }
                }
            }
        }

        @ViewBuilder private var earlier: some View {
            ReviewLabel(TasksStrings.text("tasks.late.earlier"))
            SheetCardGroup {
                ForEach(Array(check.context.reviews.enumerated()), id: \.offset) { index, review in
                    if index > 0 { InsetDivider() }
                    FactRow(
                        systemImage: review.agreed ? "checkmark" : "exclamationmark.triangle",
                        label: TasksStrings.format(
                            review.agreed ? "tasks.late.reviewAgreed" : "tasks.late.reviewReturned",
                            review.name ?? "",
                            review.role ?? ""
                        ),
                        tone: review.agreed ? .brand : .amber
                    ) {
                        if let note = review.note { ActivityNote(text: note) }
                    }
                }
            }
        }
    }
#endif
