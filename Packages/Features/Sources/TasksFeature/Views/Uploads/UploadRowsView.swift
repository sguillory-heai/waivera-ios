#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Files going up, above the task's files: waiting, sending, a short "Uploaded", or why it failed.
    struct UploadRowsView: View {
        let uploads: [UploadRow]
        let actions: UploadActions

        var body: some View {
            ForEach(Array(uploads.enumerated()), id: \.element.id) { index, row in
                if index > 0 { InsetDivider() }
                UploadRowView(row: row, actions: actions)
            }
        }
    }

    private struct UploadRowView: View {
        let row: UploadRow
        let actions: UploadActions

        var body: some View {
            let name = UploadText.name(row)
            HStack(alignment: .center, spacing: ControlSize.fieldTileGap) {
                FileKindTile(kind: row.kind, word: FileRow.short(row.kind))
                    .frame(maxHeight: .infinity, alignment: .top)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(name)
                        .waiveraTextStyle(.titleSmall, weight: .semibold)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    UploadNoteText(note: UploadText.note(row))
                    UploadProgressBar(row: row)
                    if row.problem?.canRetry == true { RetryDismiss(id: row.id, actions: actions) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.state == .failed, row.problem?.canRetry != true {
                    Button {
                        actions.dismissUpload(row.id)
                    } label: {
                        WaiveraIcon(systemName: "xmark")
                            .font(.system(size: ControlSize.iconSmall))
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(TasksStrings.format("tasks.upload.dismiss", name)))
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.minHitTarget, alignment: .leading)
        }
    }

    struct UploadNoteText: View {
        let note: UploadText.Note

        var body: some View {
            Text(note.text)
                .waiveraTextStyle(.bodySmall)
                .foregroundStyle(color)
        }

        private var color: Color {
            switch note.tone {
            case .secondary: Palette.textSecondary
            case .success: Palette.successText
            case .danger: Palette.dangerText
            case .warning: Palette.warningText
            }
        }
    }

    /// A small spinner while the file waits or sends; the server gives no byte count to show.
    struct UploadProgressBar: View {
        let row: UploadRow

        var body: some View {
            if row.state == .queued || row.state == .uploading {
                ProgressView()
                    .controlSize(.small)
                    .tint(Palette.accent)
                    .padding(.top, Spacing.xxSmall)
                    .accessibilityHidden(true)
            }
        }
    }

    struct RetryDismiss: View {
        let id: String
        let actions: UploadActions

        var body: some View {
            HStack(spacing: Spacing.small) {
                WaiveraButton(
                    TasksStrings.text("tasks.upload.retry"),
                    variant: .tonal,
                    size: .compact,
                    systemImage: "arrow.clockwise",
                    fillsWidth: false
                ) {
                    actions.retryUpload(id)
                }
                WaiveraButton(
                    TasksStrings.text("tasks.upload.remove"),
                    variant: .text,
                    size: .compact,
                    fillsWidth: false
                ) {
                    actions.dismissUpload(id)
                }
            }
        }
    }

    /// Add a file, under the task's files, with the web's limits spelled out.
    struct AddFileFooter: View {
        let onAdd: () -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                WaiveraButton(
                    TasksStrings.text("tasks.upload.add"),
                    variant: .secondary,
                    systemImage: "plus",
                    fillsWidth: true,
                    action: onAdd
                )
                Text(TasksStrings.text("tasks.upload.limits"))
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.mediumSmall)
        }
    }
#endif
