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

    private struct TaskFileScreen: View {
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

    private struct WordBlockView: View {
        let block: WordBlock

        static func headingStyle(_ level: Int) -> TextStyleToken {
            switch level {
            case ...1: .titleLarge
            case 2: .titleMedium
            default: .titleSmall
            }
        }

        var body: some View {
            switch block.kind {
            case .heading(let level):
                Text(block.text)
                    .waiveraTextStyle(Self.headingStyle(level), weight: .bold)
                    .foregroundStyle(Palette.text)
                    .padding(.top, Spacing.small)
                    .accessibilityAddTraits(.isHeader)
            case .listItem:
                HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                    Text(verbatim: "•").accessibilityHidden(true)
                    Text(block.text)
                }
                .waiveraTextStyle(.bodyMedium)
                .foregroundStyle(Palette.text)
            case .paragraph:
                Text(block.text)
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.text)
            }
        }
    }

    /// PDFKit's own view: continuous pages, pinch to zoom, VoiceOver reads the text layer.
    private struct PDFKitView: UIViewRepresentable {
        let data: Data

        func makeUIView(context: Context) -> PDFView {
            let view = PDFView()
            view.autoScales = true
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
            view.backgroundColor = UIColor(Palette.background)
            view.document = PDFDocument(data: data)
            return view
        }

        func updateUIView(_ view: PDFView, context: Context) {}
    }

    /// The image, decoded at most 2048 pixels on its long side so a phone photo never runs memory
    /// out, in a scroll view that zooms by pinch and double tap.
    private struct ZoomableImageView: UIViewRepresentable {
        static let maxPixels = 2_048
        static let maxZoom: CGFloat = 5

        let data: Data

        func makeCoordinator() -> Coordinator { Coordinator() }

        func makeUIView(context: Context) -> UIScrollView {
            let scroll = UIScrollView()
            scroll.minimumZoomScale = 1
            scroll.maximumZoomScale = Self.maxZoom
            scroll.showsHorizontalScrollIndicator = false
            scroll.showsVerticalScrollIndicator = false
            scroll.delegate = context.coordinator
            let imageView = UIImageView(image: Self.decode(data))
            imageView.contentMode = .scaleAspectFit
            imageView.isAccessibilityElement = true
            imageView.accessibilityTraits = .image
            imageView.frame = scroll.bounds
            imageView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            scroll.addSubview(imageView)
            context.coordinator.imageView = imageView
            let doubleTap = UITapGestureRecognizer(
                target: context.coordinator,
                action: #selector(Coordinator.toggleZoom)
            )
            doubleTap.numberOfTapsRequired = 2
            scroll.addGestureRecognizer(doubleTap)
            return scroll
        }

        func updateUIView(_ view: UIScrollView, context: Context) {}

        static func decode(_ data: Data) -> UIImage? {
            let options = [kCGImageSourceShouldCache: false] as CFDictionary
            guard let source = CGImageSourceCreateWithData(data as CFData, options) else { return nil }
            let thumbnail =
                [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: maxPixels,
                ] as CFDictionary
            guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnail) else { return nil }
            return UIImage(cgImage: image)
        }

        @MainActor
        final class Coordinator: NSObject, UIScrollViewDelegate {
            weak var imageView: UIImageView?

            func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }

            @objc func toggleZoom(_ gesture: UITapGestureRecognizer) {
                guard let scroll = gesture.view as? UIScrollView else { return }
                if scroll.zoomScale > scroll.minimumZoomScale {
                    scroll.setZoomScale(scroll.minimumZoomScale, animated: !UIAccessibility.isReduceMotionEnabled)
                } else {
                    let point = gesture.location(in: imageView)
                    let size = CGSize(width: scroll.bounds.width / 2.5, height: scroll.bounds.height / 2.5)
                    let rect = CGRect(
                        origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2),
                        size: size
                    )
                    scroll.zoom(to: rect, animated: !UIAccessibility.isReduceMotionEnabled)
                }
            }
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
