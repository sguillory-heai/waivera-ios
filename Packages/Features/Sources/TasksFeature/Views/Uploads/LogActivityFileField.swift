#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The file a Log activity type needs (sprout_web `LogActivityModal`): take a photo, choose
    /// one, or choose a file. It is checked as soon as it's picked, shown under the name it is
    /// saved as, and uploaded when the activity is logged.
    struct LogActivityFileField: View {
        let form: LogForm
        let model: TaskDetailModel

        @State private var source: UploadSource?

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(TasksStrings.text("tasks.log.file"))
                    .waiveraTextStyle(.labelLarge, weight: .semibold)
                    .foregroundStyle(Palette.text)
                field
                Text(message ?? TasksStrings.text("tasks.upload.limitsOne"))
                    .waiveraTextStyle(.bodySmall, weight: message == nil ? .regular : .semibold)
                    .foregroundStyle(message == nil ? Palette.textSecondary : Palette.dangerText)
            }
            .uploadPickers($source, single: true) { files in
                if let file = files.first { model.pickLogFile(file) }
            }
        }

        @ViewBuilder private var field: some View {
            if form.file != nil || form.sentAs != nil {
                CardGroup { PickedFileRow(form: form) { model.removeLogFile() } }
            } else if form.fileChecking {
                CardGroup {
                    Text(TasksStrings.text("tasks.log.fileChecking"))
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(maxWidth: .infinity, minHeight: ControlSize.minHitTarget, alignment: .leading)
                        .padding(.horizontal, Spacing.medium)
                        .padding(.vertical, Spacing.mediumSmall)
                }
            } else {
                CardGroup {
                    ForEach(Array(UploadSource.available.enumerated()), id: \.element) { index, item in
                        if index > 0 { InsetDivider() }
                        UploadSourceRow(source: item, single: true, enabled: !form.isSaving) { source = item }
                    }
                }
            }
        }

        private var message: String? {
            if let problem = form.fileProblem {
                let reason = UploadText.problem(problem)
                return form.file != nil
                    ? TasksStrings.format("tasks.log.uploadFailed", reason)
                    : TasksStrings.format("tasks.log.fileProblem", reason)
            }
            if form.showErrors, form.fileMissing, !form.fileChecking {
                return TasksStrings.text("tasks.log.fileRequired")
            }
            return nil
        }
    }

    private struct PickedFileRow: View {
        let form: LogForm
        let onRemove: () -> Void

        var body: some View {
            let name = form.sentAs ?? form.fileSavedName ?? ""
            let uploaded = form.sentAs != nil
            HStack(spacing: ControlSize.fieldTileGap) {
                let kind = form.file?.kind ?? FileKind(name: name, mimeType: nil)
                FileKindTile(kind: kind, word: FileRow.short(kind))
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(name)
                        .waiveraTextStyle(.titleSmall, weight: .semibold)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    Text(
                        [
                            TasksStrings.text(uploaded ? "tasks.upload.done" : "tasks.log.fileOnLog"),
                            form.file.map { UploadText.size($0.sizeBytes) },
                        ]
                        .compactMap(\.self)
                        .joined(separator: " · ")
                    )
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !form.isSaving, !uploaded {
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
