#if canImport(UIKit)
    import ImageIO
    import PDFKit
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// A task file, read-only: PDF pages, a zoomable image, text, or a Word file as simple text.
    /// Bytes stay in memory and go when the screen closes. Anything it can't show offers the web.
    public struct TaskFileView: View {
        let taskID: Int
        let attachmentID: Int

        @Environment(\.dataEnvironment) private var data
        @State private var model: TaskFileModel?
        @State private var sharing: SharedFile?

        public init(taskID: Int, attachmentID: Int) {
            self.taskID = taskID
            self.attachmentID = attachmentID
        }

        public var body: some View {
            Group {
                if let model {
                    TaskFileScreen(model: model)
                } else {
                    Palette.background
                }
            }
            .background(Palette.background)
            .navigationTitle(title)
            .waiveraTopBar(title, actions: actions)
            .sheet(item: $sharing) { file in
                FileShareSheet(url: file.url)
            }
            .task {
                guard model == nil, let data else { return }
                let created = TaskFileModel(taskId: taskID, attachmentId: attachmentID, environment: data)
                model = created
                await created.load()
            }
        }

        private var actions: [TopBarAction] {
            // Always there (dimmed until the file is in), so the title never reflows when it arrives.
            [
                TopBarAction(
                    id: "share",
                    systemImage: "square.and.arrow.up",
                    accessibilityLabel: TasksStrings.text("tasks.file.share"),
                    isEnabled: model?.bytes != nil
                ) {
                    sharing = model?.exportCopy().map(SharedFile.init)
                }
            ]
        }

        private var title: String {
            guard let name = model?.name, !name.isEmpty else { return TasksStrings.text("tasks.file.viewer") }
            return name
        }
    }

    struct SharedFile: Identifiable {
        let url: URL
        var id: URL { url }
    }

    /// The system share sheet (Save to Files, AirDrop, Mail, another app). The copy it was given
    /// is removed when it closes, whether or not it was sent.
    struct FileShareSheet: UIViewControllerRepresentable {
        let url: URL

        func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            let folder = url.deletingLastPathComponent()
            controller.completionWithItemsHandler = { _, _, _, _ in
                try? FileManager.default.removeItem(at: folder)
            }
            return controller
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }

    #if DEBUG
        private struct FilePreview: View {
            var body: some View {
                NavigationStack { TaskFileView(taskID: 12, attachmentID: 44) }
                    .fakeDataEnvironment()
            }
        }

        #Preview("Light") { FilePreview() }
        #Preview("Dark") { FilePreview().preferredColorScheme(.dark) }
        #Preview("AX5") { FilePreview().dynamicTypeSize(.accessibility5) }
    #endif
#endif
