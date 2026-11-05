#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    /// What to do with a tapped task file (Android `TaskFileActionsSheet`): look at it, keep a
    /// copy on the phone, or send it on.
    struct TaskFileActionsSheet: View {
        let sheet: TaskFileActionsModel.Sheet
        let model: TaskFileActionsModel
        let onOpen: () -> Void

        @State private var contentHeight: CGFloat = 0

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    header
                    CardGroup {
                        row(
                            systemImage: sheet.row.viewable ? "wv-view" : "arrow.up.right.square",
                            tone: .brand,
                            title: TasksStrings.text(sheet.row.viewable ? "tasks.file.open" : "tasks.file.openWeb"),
                            busy: false,
                            action: onOpen
                        )
                        InsetDivider()
                        row(
                            systemImage: "square.and.arrow.down",
                            tone: .teal,
                            title: TasksStrings.text("tasks.file.save"),
                            busy: sheet.busy == .save
                        ) { model.run(.save) }
                        InsetDivider()
                        row(
                            systemImage: "square.and.arrow.up",
                            tone: .amber,
                            title: TasksStrings.text("tasks.file.shareAction"),
                            busy: sheet.busy == .share
                        ) { model.run(.share) }
                    }
                }
                .padding(Spacing.gutter)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { contentHeight = $0 }
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.surface)
            .presentationDetents(contentHeight > 0 ? [.height(contentHeight), .large] : [.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(Radius.modalSheet)
            .presentationBackground(Palette.surface)
            // Over this sheet, so the copy is handed on without a second sheet racing this one's close.
            .sheet(
                item: Binding(get: { model.handoff }, set: { if $0 == nil { model.handoffClosed() } }),
                onDismiss: { model.handoffClosed() }
            ) { handoff in
                switch handoff.action {
                case .save:
                    FileExportPicker(url: handoff.url) { saved in model.saved(saved) }
                        .ignoresSafeArea()
                case .share:
                    FileShareSheet(url: handoff.url)
                }
            }
        }

        private var header: some View {
            HStack(alignment: .top, spacing: ControlSize.fieldTileGap) {
                FileKindTile(kind: sheet.row.kind, word: sheet.row.short)
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    // A long name wraps instead of being cut, so the person knows which file they picked.
                    Text(sheet.row.name)
                        .waiveraTextStyle(.titleMedium)
                        .foregroundStyle(Palette.text)
                    Text([sheet.row.kindLabel, sheet.row.size].joined(separator: " · "))
                        .waiveraTextStyle(.bodySmall)
                        .foregroundStyle(Palette.textSecondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, Spacing.small)
            .accessibilityElement(children: .combine)
        }

        private func row(
            systemImage: String,
            tone: TileTone,
            title: String,
            busy: Bool,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                ListRow(title: title) {
                    IconTile(
                        systemImage: systemImage,
                        tone: tone,
                        size: ControlSize.fieldTile,
                        glyphSize: ControlSize.fieldTileGlyph
                    )
                } trailing: {
                    if busy {
                        ProgressView()
                    } else {
                        WaiveraIcon(systemName: "chevron.right")
                            .font(.system(size: ControlSize.iconSmall))
                            .foregroundStyle(Palette.textSecondary)
                    }
                }
                .contentShape(Rectangle())
                .opacity(sheet.busy == nil || busy ? 1 : Emphasis.disabled)
            }
            .buttonStyle(.press(.row))
            .disabled(sheet.busy != nil)
            .accessibilityValue(Text(busy ? TasksStrings.text("tasks.file.preparing") : ""))
        }
    }

    /// The Files picker for a downloaded copy ("Save to phone"); the copy's folder goes when it closes.
    struct FileExportPicker: UIViewControllerRepresentable {
        let url: URL
        let onFinish: (Bool) -> Void

        func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

        func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
            let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
            picker.delegate = context.coordinator
            return picker
        }

        func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

        @MainActor
        final class Coordinator: NSObject, UIDocumentPickerDelegate {
            let onFinish: (Bool) -> Void

            init(onFinish: @escaping (Bool) -> Void) { self.onFinish = onFinish }

            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                onFinish(true)
            }

            func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                onFinish(false)
            }
        }
    }
#endif
