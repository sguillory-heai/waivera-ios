#if canImport(UIKit)
    import ImageIO
    import PDFKit
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    struct TaskFileScreen: View {
        let model: TaskFileModel

        @Environment(\.openURL) private var openURL
        @State private var retries = 0

        var body: some View {
            // One loader across every phase, so a slow file shows document lines (Android
            // `LoadingPage`) and hands over with a fade, and a fast one never flashes them.
            LoadingContent(isLoading: isLoading) {
                switch model.phase {
                case .loading:
                    EmptyView()
                case .failed:
                    failed
                case .ready(let content):
                    FileContentView(content: content, webURL: model.webURL)
                }
            } skeleton: {
                DocumentSkeleton()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(Text(TasksStrings.text("tasks.file.loading")))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }

        private var isLoading: Bool {
            if case .loading = model.phase { return true }
            return false
        }

        private var failed: some View {
            VStack(spacing: Spacing.medium) {
                EmptyStateView.error(
                    title: TasksStrings.text("tasks.file.failed"),
                    message: "",
                    onRetry: { retries += 1 }
                )
                if let web = model.webURL {
                    WaiveraButton(
                        TasksStrings.text("tasks.file.openWeb"),
                        variant: .secondary,
                        systemImage: "safari"
                    ) {
                        openURL(web)
                    }
                }
            }
            .padding(Spacing.gutter)
            .frame(maxHeight: .infinity)
            .task(id: retries) {
                if retries > 0 { await model.load() }
            }
        }
    }
#endif
