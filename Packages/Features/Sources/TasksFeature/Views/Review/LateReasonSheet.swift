#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// The late reason (Android `LateReasonSheet`), sent before a late task moves on or corrected
    /// by a reviewer: the reason, what happened, and the file a reason may need.
    struct LateReasonSheet: View {
        let form: LateForm
        let today: CalendarDate
        let model: TaskReviewModel

        var body: some View {
            ReviewSheetFrame(
                title: TasksStrings.text(form.editingId != nil ? "tasks.late.editTitle" : "tasks.late.title"),
                isSaving: form.isSaving
            ) {
                if form.editingId == nil, let due = form.due {
                    Text(TasksStrings.format("tasks.late.due", TaskFormat.date(due, today: today)))
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
                banners
                reasons
                ReviewTextArea(
                    label: TasksStrings.text("tasks.late.explanation"),
                    placeholder: TasksStrings.text("tasks.late.explanationPlaceholder"),
                    text: form.explanation,
                    error: explanationError,
                    enabled: !form.isSaving
                ) { model.setLateExplanation($0) }
                if form.reason?.requiresEvidence == true { LateEvidenceField(form: form, model: model) }
            } bar: {
                WaiveraButton(
                    TasksStrings.text(form.editingId != nil ? "tasks.late.save" : "tasks.late.send"),
                    size: .large,
                    isLoading: form.isSaving,
                    loadingTitle: TasksStrings.text("tasks.review.sending"),
                    fillsWidth: true
                ) { model.submitLate() }
                .disabled(form.evidenceChecking || form.explanationTooLong)
            }
        }

        @ViewBuilder private var banners: some View {
            if form.failed { BannerView(.error, message: TasksStrings.text("tasks.late.failed")) }
            if form.returned {
                BannerView(
                    .warning,
                    title: TasksStrings.text("tasks.late.returnedTitle"),
                    message: form.correction.map { TasksStrings.format("tasks.late.returnedNote", $0) }
                        ?? TasksStrings.text("tasks.late.returnedFix")
                )
            }
            if form.delayId != nil {
                BannerView(
                    .info,
                    title: TasksStrings.text("tasks.late.delayTitle"),
                    message: TasksStrings.text("tasks.late.delayMessage"),
                    actionTitle: TasksStrings.text("tasks.late.delayDrop"),
                    action: { model.dropDelay() }
                )
            }
        }

        @ViewBuilder private var reasons: some View {
            switch form.reasons {
            case .loading:
                ReviewLabel(TasksStrings.text("tasks.late.reason"))
                SkeletonBlock(height: ControlSize.fieldHeight)
            case .failed:
                ReviewLabel(TasksStrings.text("tasks.late.reason"))
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.late.reasonsError"),
                    message: "",
                    onRetry: { model.loadLateReasons() }
                )
            case .ready(let reasons):
                ReviewMenuField(
                    label: TasksStrings.text("tasks.late.reason"),
                    value: form.reason?.name,
                    placeholder: TasksStrings.text("tasks.late.chooseReason"),
                    error: form.showErrors && form.reasonMissing ? TasksStrings.text("tasks.late.chooseReason") : nil,
                    enabled: !form.isSaving
                ) {
                    ForEach(reasons) { reason in
                        Button {
                            model.setLateReason(reason.id)
                        } label: {
                            if reason.id == form.reasonId {
                                Label(reason.name, systemImage: "checkmark")
                            } else {
                                Text(reason.name)
                            }
                        }
                    }
                }
                if let detail = form.reason?.description { ReviewNote(text: detail) }
            }
        }

        private var explanationError: String? {
            if let over = ReviewTextArea.overLimit(form.explanation, limit: LateForm.maxExplanation) { return over }
            guard form.showErrors, form.explanationMissing else { return nil }
            return TasksStrings.text("tasks.late.explanationRequired")
        }
    }

    /// The file a late reason needs: the picked one (sent with the reason), one already on it, or
    /// the camera, photos and Files.
    private struct LateEvidenceField: View {
        let form: LateForm
        let model: TaskReviewModel

        @State private var source: UploadSource?

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ReviewLabel(TasksStrings.text("tasks.late.evidence"))
                CardGroup { field }
                if let message { ReviewNote(text: message, tone: .error) } else {
                    ReviewNote(
                        text: TasksStrings.text(
                            form.evidenceChecking ? "tasks.log.fileChecking" : "tasks.late.evidenceNeeded"
                        )
                    )
                }
            }
            .uploadPickers($source, single: true) { model.pickEvidence($0) }
        }

        @ViewBuilder private var field: some View {
            if let file = form.evidence {
                EvidenceRow(
                    name: file.name,
                    note: [TasksStrings.text("tasks.late.evidencePending"), UploadText.size(file.sizeBytes)]
                        .joined(separator: " · "),
                    kind: file.kind,
                    onRemove: form.isSaving ? nil : { model.removeEvidence() }
                )
            } else if form.keptEvidenceId != nil {
                EvidenceRow(
                    name: TasksStrings.text("tasks.late.evidenceKept"),
                    note: TasksStrings.text("tasks.upload.done"),
                    kind: FileKind(name: "", mimeType: nil),
                    onRemove: form.uploadedEvidenceId == nil || form.isSaving ? nil : { model.removeEvidence() }
                )
            } else {
                ForEach(Array(UploadSource.available.enumerated()), id: \.element) { index, item in
                    if index > 0 { InsetDivider() }
                    UploadSourceRow(source: item, single: true, enabled: !form.isSaving && !form.evidenceChecking) {
                        source = item
                    }
                }
            }
        }

        private var message: String? {
            if let problem = form.evidenceProblem {
                return TasksStrings.format("tasks.late.evidenceFailed", UploadText.problem(problem))
            }
            if form.showErrors, form.evidenceMissing { return TasksStrings.text("tasks.late.evidenceRequired") }
            return nil
        }
    }

    private struct EvidenceRow: View {
        let name: String
        let note: String
        let kind: FileKind
        let onRemove: (() -> Void)?

        var body: some View {
            HStack(spacing: ControlSize.fieldTileGap) {
                FileKindTile(kind: kind, word: FileRow.short(kind))
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(name)
                        .waiveraTextStyle(.titleSmall, weight: .semibold)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    Text(note).waiveraTextStyle(.bodySmall).foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let onRemove {
                    Button(action: onRemove) {
                        WaiveraIcon(systemName: "xmark")
                            .font(.system(size: ControlSize.iconSmall))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(TasksStrings.format("tasks.log.fileRemove", name)))
                }
            }
            .padding(.leading, Spacing.medium)
            .padding(.trailing, Spacing.extraSmall)
            .padding(.vertical, Spacing.mediumSmall)
        }
    }
#endif
