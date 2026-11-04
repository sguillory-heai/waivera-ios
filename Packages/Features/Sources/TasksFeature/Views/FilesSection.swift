#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The task's files, newest first. PDFs, images, text and Word files open in the phone's
    /// read-only viewer; anything else, or anything too large, opens the task on the web.
    /// Hidden when the task has no files.
    struct FilesSection: View {
        let files: Loadable<[FileRow]>
        let onOpen: (FileRow) -> Void
        let onRetry: () -> Void

        var body: some View {
            if case .ready(let rows) = files, rows.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    let count = files.value?.count ?? 0
                    TaskSectionTitle(
                        TasksStrings.text("tasks.files.title"),
                        count: count,
                        countLabel: TasksStrings.plural("tasks.files.count", count)
                    )
                    Group {
                        switch files {
                        case .loading:
                            SkeletonList(rows: 1)
                        case .failed:
                            EmptyStateView.error(
                                title: TasksStrings.text("tasks.files.error"),
                                message: "",
                                onRetry: onRetry
                            )
                        case .ready(let rows):
                            SheetCardGroup {
                                ForEach(rows) { row in
                                    Button {
                                        onOpen(row)
                                    } label: {
                                        FileRowView(row: row)
                                    }
                                    .buttonStyle(.press(.row))
                                    .accessibilityLabel(Text(row.accessibilityLabel))
                                    .accessibilityHint(
                                        Text(TasksStrings.text(row.viewable ? "tasks.file.open" : "tasks.file.openWeb"))
                                    )
                                }
                            }
                        }
                    }
                    .padding(.horizontal, Spacing.gutter)
                }
            }
        }
    }

    struct FileRowView: View {
        let row: FileRow

        var body: some View {
            HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                FileKindTile(kind: row.kind, word: row.short)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(row.name)
                        .waiveraTextStyle(.titleSmall, weight: .semibold)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    Text(row.meta)
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                    if let addedBy = row.addedBy {
                        Text(TasksStrings.format("tasks.file.addedBy", addedBy))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                            .lineLimit(1)
                    }
                    if let note = row.webNote {
                        Text(note)
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.accent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: row.viewable ? "chevron.right" : "arrow.up.right.square")
                    .font(.system(size: ControlSize.iconSmall))
                    .foregroundStyle(row.viewable ? Palette.textSecondary : Palette.accent)
                    .frame(maxHeight: .infinity)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.mediumSmall)
            .frame(minHeight: ControlSize.minHitTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    /// The file type as a short word on a coloured tile, so a PDF and a photo read apart at a
    /// glance. Fixed size: the type is spelled out in the scaling line under the name.
    struct FileKindTile: View {
        let kind: FileKind
        let word: String

        var body: some View {
            Text(word)
                .font(.system(size: ControlSize.tileWord, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(tone.contentColor)
                .frame(width: ControlSize.fieldTile, height: ControlSize.fieldTile)
                .background(tone.containerColor, in: RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                .accessibilityHidden(true)
        }

        private var tone: TileTone {
            switch kind {
            case .pdf: .rose
            case .image: .teal
            case .word: .brand
            case .text: .amber
            case .other: .neutral
            }
        }
    }

    private struct FilesPreview: View {
        var body: some View {
            let rows = [
                FileRow(
                    id: 1,
                    name: "Care plan 2026.pdf",
                    kind: .pdf,
                    size: "182 KB",
                    added: "Today",
                    addedBy: "Dana Cole",
                    viewable: true
                ),
                FileRow(id: 2, name: "Budget.xlsx", kind: .other, size: "30 KB", added: "Oct 28", viewable: false),
            ]
            ScrollView { FilesSection(files: .ready(rows), onOpen: { _ in }, onRetry: {}).padding(Spacing.gutter) }
                .background(Palette.background)
        }
    }

    #Preview("Light") { FilesPreview() }
    #Preview("Dark") { FilesPreview().preferredColorScheme(.dark) }
    #Preview("AX5") { FilesPreview().dynamicTypeSize(.accessibility5) }
#endif
