#if canImport(UIKit)
    import ImageIO
    import PDFKit
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    struct FileContentView: View {
        let content: FileContent
        let webURL: URL?

        @Environment(\.openURL) private var openURL

        var body: some View {
            switch content {
            case .pdf(let data):
                PDFKitView(data: data)
                    .ignoresSafeArea(edges: .bottom)
            case .image(let data):
                ZoomableImageView(data: data)
                    .ignoresSafeArea(edges: .bottom)
            case .text(let text, let cut):
                ScrollView {
                    VStack(alignment: .leading, spacing: Spacing.medium) {
                        if cut {
                            BannerView(
                                .info,
                                message: TasksStrings.text("tasks.file.textCut"),
                                actionTitle: webURL == nil ? nil : TasksStrings.text("tasks.file.openWeb"),
                                action: webURL.map { url in { openURL(url) } }
                            )
                        }
                        Text(text)
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.text)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(Spacing.gutter)
                }
            case .word(let blocks):
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Spacing.small) {
                        ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                            WordBlockView(block: block)
                        }
                    }
                    .padding(Spacing.gutter)
                    .textSelection(.enabled)
                }
            }
        }
    }
#endif
