#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    /// How an employee task's files are finalized (Android `ClosureSheet`): close each, or merge
    /// PDFs in a chosen order, and the next policy expiration for an insurance renewal.
    struct ClosureSheet: View {
        let form: ClosureForm
        let today: CalendarDate
        let model: TaskReviewModel

        var body: some View {
            ReviewSheetFrame(
                title: TasksStrings.text(
                    form.options.needsExpiration ? "tasks.review.closureInsurance" : "tasks.review.closureTitle"
                ),
                isSaving: form.isSaving
            ) {
                if form.failed { BannerView(.error, message: TasksStrings.text("tasks.review.closureFailed")) }
                if form.options.canMerge {
                    // Choice cards, not a segmented control: "Close & merge PDFs" must stay whole at large text.
                    ChoiceRow(
                        title: TasksStrings.text("tasks.review.closureClose"),
                        detail: TasksStrings.text("tasks.review.closureCloseDetail"),
                        selected: !form.merge,
                        enabled: !form.isSaving
                    ) { model.setMerge(false) }
                    ChoiceRow(
                        title: TasksStrings.text("tasks.review.closureMerge"),
                        detail: TasksStrings.text("tasks.review.closureMergeDetail"),
                        selected: form.merge,
                        enabled: !form.isSaving
                    ) { model.setMerge(true) }
                }
                if form.merge { mergeOrder }
                if form.options.needsExpiration {
                    ReviewDateField(
                        label: TasksStrings.text("tasks.review.closureExpiration"),
                        value: form.expiration,
                        today: today,
                        error: form.showErrors && form.expirationMissing
                            ? TasksStrings.text("tasks.review.closureExpirationRequired") : nil,
                        enabled: !form.isSaving
                    ) { model.setExpiration($0) }
                    ReviewNote(text: TasksStrings.text("tasks.review.closureExpirationNote"))
                }
            } bar: {
                WaiveraButton(
                    TasksStrings.text("tasks.review.continue"),
                    size: .large,
                    isLoading: form.isSaving,
                    loadingTitle: TasksStrings.text("tasks.review.sending"),
                    fillsWidth: true
                ) { model.saveClosure() }
            }
        }

        @ViewBuilder private var mergeOrder: some View {
            let byId = Dictionary(form.options.pdfs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            ReviewLabel(TasksStrings.text("tasks.review.closureOrder"))
            SheetCardGroup {
                ForEach(Array(form.order.enumerated()), id: \.element) { index, id in
                    if let pdf = byId[id] {
                        if index > 0 { InsetDivider(inset: Spacing.medium) }
                        PdfOrderRow(
                            pdf: pdf,
                            picked: form.picked.contains(id),
                            first: index == 0,
                            last: index == form.order.count - 1,
                            enabled: !form.isSaving,
                            model: model
                        )
                    }
                }
            }
            if form.tooFewPicked {
                ReviewNote(
                    text: TasksStrings.text("tasks.review.closureTooFew"),
                    tone: form.showErrors ? .error : .help
                )
            }
        }
    }

    /// One PDF in the merge: picked or not, and moved up or down the order.
    private struct PdfOrderRow: View {
        let pdf: ClosurePdf
        let picked: Bool
        let first: Bool
        let last: Bool
        let enabled: Bool
        let model: TaskReviewModel

        var body: some View {
            HStack(spacing: 0) {
                Button {
                    model.togglePdf(pdf.id)
                } label: {
                    HStack(spacing: Spacing.small) {
                        WaiveraIcon(systemName: picked ? "checkmark.square.fill" : "square")
                            .foregroundStyle(picked ? Palette.accent : Palette.textSecondary)
                        Text(pdf.name)
                            .waiveraTextStyle(.fieldValue)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.leading, Spacing.medium)
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(picked ? [.isSelected] : [])
                move(up: true, enabled: !first)
                move(up: false, enabled: !last)
            }
            .disabled(!enabled)
            .frame(minHeight: ControlSize.listRowMinHeight)
        }

        private func move(up: Bool, enabled: Bool) -> some View {
            Button {
                model.movePdf(pdf.id, up: up)
            } label: {
                WaiveraIcon(systemName: up ? "arrow.up" : "arrow.down")
                    .foregroundStyle(enabled ? Palette.textSecondary : Palette.textTertiary)
                    .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(!enabled)
            .accessibilityLabel(
                Text(TasksStrings.format(up ? "tasks.review.closureUp" : "tasks.review.closureDown", pdf.name))
            )
        }
    }
#endif
