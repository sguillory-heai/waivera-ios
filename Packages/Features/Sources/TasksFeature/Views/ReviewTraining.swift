#if canImport(UIKit)
    import SwiftUI
    import UniformTypeIdentifiers
    import WaiveraData
    import WaiveraDesign

    /// External training credit (sprout_web `ExternalTrainingReview`): the course, who taught it
    /// and the certificate, which opens in its own viewer.
    struct ReviewTraining: View {
        let training: Loadable<TrainingCredit>
        let opening: Bool
        let onRetry: () -> Void
        let onOpenCertificate: () -> Void

        var body: some View {
            switch training {
            case .loading:
                SheetCardGroup {
                    FactRow(systemImage: "rosette", label: TasksStrings.text("tasks.review.course")) {
                        SkeletonBlock(width: ControlSize.avatarLarge * 2, height: ControlSize.skeletonLine)
                    }
                }
                .accessibilityLabel(Text(TasksStrings.text("tasks.requests.loading")))
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.review.trainingFailed"),
                    message: "",
                    onRetry: onRetry
                )
            case .ready(let credit):
                details(credit)
                if credit.decidable && credit.needsApproveReason {
                    FactNote(text: TasksStrings.format("tasks.review.uploadedYourself", credit.employeeName))
                }
                if !credit.decidable, let blocked = credit.blocked {
                    FactNote(text: Self.text(blocked))
                }
            }
        }

        private func details(_ credit: TrainingCredit) -> some View {
            let notRecorded = TasksStrings.text("tasks.review.notRecorded")
            return SheetCardGroup {
                FactRow(systemImage: "rosette", label: TasksStrings.text("tasks.review.course")) {
                    FactValue(text: credit.course)
                    let hours = RequestItems.hours(credit.hours)
                    FactNote(
                        text: credit.completed.map {
                            TasksStrings.format("tasks.review.completed", hours, TaskFormat.fullDate($0))
                        } ?? hours
                    )
                }
                InsetDivider()
                FactRow(systemImage: "person", label: TasksStrings.text("tasks.review.trainer")) {
                    FactValue(text: credit.trainer ?? notRecorded)
                }
                InsetDivider()
                FactRow(systemImage: "building.2", label: TasksStrings.text("tasks.review.provider")) {
                    FactValue(text: credit.provider ?? notRecorded)
                }
                if let uploader = credit.uploadedBy {
                    InsetDivider()
                    FactRow(systemImage: "arrow.up.doc", label: TasksStrings.text("tasks.review.uploadedBy")) {
                        FactValue(text: uploader)
                    }
                }
                InsetDivider()
                Button(action: onOpenCertificate) {
                    FactRow(systemImage: "paperclip", label: TasksStrings.text("tasks.review.certificate"), showsChevron: true) {
                        FactValue(text: TasksStrings.text("tasks.review.viewCertificate"), color: Palette.link)
                        if opening { FactNote(text: TasksStrings.text("tasks.review.certificateOpening")) }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.card))
                .disabled(opening)
            }
        }

        static func text(_ block: TrainingBlock) -> String {
            switch block {
            case .ownCredit: TasksStrings.text("tasks.review.blockedOwn")
            case .noReviewer: TasksStrings.text("tasks.review.blockedNoReviewer")
            case .notReviewer: TasksStrings.text("tasks.review.blockedNotReviewer")
            }
        }
    }

    /// The training decision's confirm step: rejecting always asks why, so the employee can fix
    /// the certificate; approving asks only when the reviewer uploaded it themselves.
    struct TrainingDecisionSheet: View {
        let title: String
        let message: String
        let approve: Bool
        let credit: TrainingCredit
        let reason: Binding<String>
        let canConfirm: Bool
        let onConfirm: () -> Void

        @Environment(\.dismiss) private var dismiss

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    IconTile(
                        systemImage: approve ? "checkmark" : "xmark",
                        tone: approve ? .brand : .danger,
                        size: ControlSize.cardTile
                    )
                    Text(title)
                        .waiveraTextStyle(.titleLarge, weight: .bold)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Text(message)
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                    if approve && credit.needsApproveReason {
                        FactNote(text: TasksStrings.format("tasks.review.uploadedYourself", credit.employeeName))
                    }
                    let required = !approve || credit.needsApproveReason
                    Text(TasksStrings.text(required ? "tasks.review.reasonRequired" : "tasks.review.reasonOptional"))
                        .waiveraTextStyle(.fieldLabel)
                        .foregroundStyle(Palette.textSecondary)
                    TextField(TasksStrings.text("tasks.review.reasonPlaceholder"), text: reason, axis: .vertical)
                        .lineLimit(3...8)
                        .waiveraTextStyle(.bodyLarge)
                        .padding(Spacing.medium)
                        .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                    WaiveraButton(
                        TasksStrings.text(approve ? "tasks.review.approveCredit" : "tasks.review.rejectSubmission"),
                        variant: approve ? .primary : .destructive,
                        size: .large,
                        systemImage: approve ? "checkmark" : "xmark",
                        fillsWidth: true,
                        action: onConfirm
                    )
                    .disabled(!canConfirm)
                    WaiveraButton(
                        TasksStrings.text("tasks.cancel"),
                        variant: .secondary,
                        size: .large,
                        fillsWidth: true
                    ) {
                        dismiss()
                    }
                }
                .padding(Spacing.gutter)
            }
            .background(Palette.surface)
        }
    }

    /// The training certificate, read-only, with the system share sheet to save or send it.
    struct CertificateSheet: View {
        let file: DownloadedFile

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text(TasksStrings.text("tasks.review.certificate"))
                        .waiveraTextStyle(.titleSmall)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    ShareLink(item: CertificateDocument(file: file), preview: SharePreview(file.name)) {
                        WaiveraIcon(systemName: "square.and.arrow.up")
                            .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget)
                    }
                    .accessibilityLabel(Text(TasksStrings.text("tasks.file.share")))
                }
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.small)
                PDFKitView(data: file.data)
            }
            .background(Palette.background)
        }
    }

    /// Shares the bytes under a readable name, so Files and Mail keep "Training certificate.pdf".
    struct CertificateDocument: Transferable {
        let file: DownloadedFile

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(exportedContentType: .pdf) { $0.file.data }
                .suggestedFileName(TasksStrings.text("tasks.review.certificateFile"))
        }
    }
#endif
