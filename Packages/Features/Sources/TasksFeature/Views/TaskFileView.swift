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
            .waiveraTopBar(title)
            .task {
                guard model == nil, let data else { return }
                let created = TaskFileModel(taskId: taskID, attachmentId: attachmentID, environment: data)
                model = created
                await created.load()
            }
        }

        private var title: String {
            guard let name = model?.name, !name.isEmpty else { return TasksStrings.text("tasks.file.viewer") }
            return name
        }
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
