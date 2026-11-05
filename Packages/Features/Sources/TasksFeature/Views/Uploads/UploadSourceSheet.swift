#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The Add a file sheet (Android `UploadSourceSheet`): where the file goes, then the camera,
    /// photos or Files. An extra file on an employee task is filed under a category first, as
    /// the web's upload modal asks.
    struct UploadSourceSheet: View {
        let sheet: UploadSheet
        let model: TaskUploadsModel

        @State private var source: UploadSource?
        @State private var contentHeight: CGFloat = 0
        @State private var barHeight: CGFloat = 0

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        if sheet.needsCategory { category }
                        sources
                        Text(TasksStrings.text(sheet.single ? "tasks.upload.limitsOne" : "tasks.upload.limits"))
                            .waiveraTextStyle(.bodySmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .padding(Spacing.gutter)
                    .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
                }
                .onGeometryChange(for: CGFloat.self, of: \.safeAreaInsets.top) { barHeight = $0 }
                .background(Palette.surface)
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents(
                contentHeight > 0 ? [.height(contentHeight + barHeight), .large] : [.medium, .large]
            )
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.modalSheet)
            .presentationBackground(Palette.surface)
            .uploadPickers($source, single: sheet.single) { files in
                model.picked(files, target: sheet.target, single: sheet.single)
            }
        }

        private var title: String {
            sheet.title.map { TasksStrings.format("tasks.upload.titleFor", $0) }
                ?? TasksStrings.text("tasks.upload.add")
        }

        @ViewBuilder private var category: some View {
            Text(TasksStrings.text("tasks.upload.category"))
                .waiveraTextStyle(.labelLarge, weight: .semibold)
                .foregroundStyle(Palette.text)
            switch sheet.categories {
            case .loading:
                Text(TasksStrings.text("tasks.upload.categoriesLoading"))
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(minHeight: ControlSize.fieldHeight)
            case .failed:
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.upload.categoriesError"),
                    message: "",
                    onRetry: { model.loadCategories() }
                )
            case .ready(let list):
                Menu {
                    ForEach(list) { item in
                        Button(item.name) { model.pickCategory(item.id) }
                    }
                } label: {
                    let picked = list.first { $0.id == sheet.target.categoryId }
                    HStack {
                        Text(picked?.name ?? TasksStrings.text("tasks.upload.categoryPlaceholder"))
                            .foregroundStyle(picked == nil ? Palette.textTertiary : Palette.text)
                        Spacer()
                        WaiveraIcon(systemName: "chevron.up.chevron.down").foregroundStyle(Palette.textSecondary)
                    }
                    .waiveraTextStyle(.bodyLarge)
                    .padding(.horizontal, Spacing.medium)
                    .frame(minHeight: ControlSize.fieldHeight)
                    .background(Palette.field, in: RoundedRectangle(cornerRadius: Radius.field))
                }
                .accessibilityLabel(Text(TasksStrings.text("tasks.upload.category")))
                if !sheet.ready {
                    Text(TasksStrings.text("tasks.upload.categoryFirst"))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                }
            }
        }

        private var sources: some View {
            CardGroup {
                ForEach(Array(UploadSource.available.enumerated()), id: \.element) { index, item in
                    if index > 0 { InsetDivider() }
                    UploadSourceRow(source: item, single: sheet.single, enabled: sheet.ready) { source = item }
                }
            }
        }
    }

    /// One way to pick a file: an icon tile, what it does, and where the file comes from.
    struct UploadSourceRow: View {
        let source: UploadSource
        let single: Bool
        var enabled = true
        let onTap: () -> Void

        var body: some View {
            Button(action: onTap) {
                ListRow(title: source.title(single: single), subtitle: source.detail, showsChevron: true) {
                    IconTile(
                        systemImage: source.systemImage,
                        tone: source.tone,
                        size: ControlSize.fieldTile,
                        glyphSize: ControlSize.fieldTileGlyph
                    )
                } trailing: {
                    EmptyView()
                }
                .contentShape(Rectangle())
                .opacity(enabled ? 1 : Emphasis.disabled)
            }
            .buttonStyle(.press(.row))
            .disabled(!enabled)
        }
    }
#endif
