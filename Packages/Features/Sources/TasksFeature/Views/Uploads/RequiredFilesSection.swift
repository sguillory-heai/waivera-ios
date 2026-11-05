#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    struct UploadActions {
        var uploadRequired: (Int) -> Void = { _ in }
        var openForm: () -> Void = {}
        var retryRequired: () -> Void = {}
        var addFile: () -> Void = {}
        var retryUpload: (String) -> Void = { _ in }
        var dismissUpload: (String) -> Void = { _ in }
    }

    /// The files the task still needs (sprout_web "Required files"). Each takes one upload; a
    /// form is filled on the web. Hidden when nothing is missing, or while the list loads.
    struct RequiredFilesSection: View {
        let required: Loadable<[RequiredRow]>
        let canUpload: Bool
        let actions: UploadActions

        var body: some View {
            switch required {
            case .loading:
                EmptyView()
            case .ready(let rows) where rows.isEmpty:
                EmptyView()
            default:
                VStack(alignment: .leading, spacing: 0) {
                    let rows = required.value ?? []
                    let missing = rows.filter { $0.upload?.state != .done }.count
                    CountedSectionHeader(
                        TasksStrings.text("tasks.required.title"),
                        count: missing > 0 ? missing : nil,
                        countLabel: TasksStrings.plural("tasks.required.count", missing),
                        tone: .attention
                    )
                    .padding(.leading, Spacing.gutter + Spacing.extraSmall)
                    .padding(.trailing, Spacing.gutter)
                    .padding(.top, Spacing.mediumPlus)
                    .padding(.bottom, Spacing.small)
                    SheetCardGroup {
                        if required == .failed {
                            EmptyStateView.error(
                                title: TasksStrings.text("tasks.required.error"),
                                message: "",
                                onRetry: actions.retryRequired
                            )
                        } else {
                            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                                if index > 0 { InsetDivider() }
                                RequiredRowView(row: row, canUpload: canUpload, actions: actions)
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
        }
    }

    private struct RequiredRowView: View {
        let row: RequiredRow
        let canUpload: Bool
        let actions: UploadActions

        @Environment(\.dynamicTypeSize) private var typeSize

        private var showsButton: Bool {
            canUpload && !row.isForm && (row.upload == nil || row.upload?.problem?.canRetry == false)
        }

        var body: some View {
            if row.isForm {
                Button(action: actions.openForm) { content }
                    .buttonStyle(.press(.row))
                    .accessibilityHint(Text(TasksStrings.text("tasks.file.openWeb")))
            } else {
                content
            }
        }

        private var content: some View {
            // At large text the button sits under the name, so the name keeps the row's width.
            let stacked = typeSize.isAccessibilitySize
            let note = UploadText.note(row)
            return HStack(alignment: .center, spacing: ControlSize.fieldTileGap) {
                IconTile(
                    systemImage: row.isForm ? "checklist" : "paperclip",
                    tone: row.isForm ? .neutral : .amber,
                    size: ControlSize.fieldTile,
                    glyphSize: ControlSize.fieldTileGlyph
                )
                .frame(maxHeight: .infinity, alignment: .top)
                .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(row.name)
                        .waiveraTextStyle(.titleSmall, weight: .semibold)
                        .foregroundStyle(Palette.text)
                    UploadNoteText(note: note)
                    if let upload = row.upload {
                        UploadProgressBar(row: upload)
                        if upload.problem?.canRetry == true { RetryDismiss(id: upload.id, actions: actions) }
                    }
                    if showsButton && stacked { uploadButton }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if row.isForm {
                    WaiveraIcon(systemName: "arrow.up.right.square")
                        .font(.system(size: ControlSize.iconSmall))
                        .foregroundStyle(Palette.link)
                        .accessibilityHidden(true)
                } else if showsButton && !stacked {
                    uploadButton
                }
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }

        private var uploadButton: some View {
            WaiveraButton(
                TasksStrings.text("tasks.upload"),
                variant: .tonal,
                size: .compact,
                systemImage: "arrow.up.doc",
                fillsWidth: false
            ) {
                actions.uploadRequired(row.id)
            }
            .accessibilityLabel(Text(TasksStrings.format("tasks.upload.for", row.name)))
        }
    }
#endif
