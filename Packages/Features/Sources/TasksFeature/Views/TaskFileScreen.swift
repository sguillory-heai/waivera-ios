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
            switch model.phase {
            case .loading:
                LoadingContent(isLoading: true) {
                    EmptyView()
                } skeleton: {
                    SkeletonList(rows: 4)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Text(TasksStrings.text("tasks.file.loading")))
                }
            case .failed:
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
            case .ready(let content):
                FileContentView(content: content, webURL: model.webURL)
            }
        }
    }
#endif
