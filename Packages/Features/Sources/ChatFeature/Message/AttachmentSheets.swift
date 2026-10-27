#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraDesign

    /// Save to Files or Open / Share for a downloaded file (03 §8).
    struct FileActionsSheet: View {
        let fileName: String
        let isBusy: Bool
        let preparedFile: PreparedFile?
        let onSave: () -> Void
        let onShare: () -> Void
        let onFinish: (_ completed: Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                Text(fileName)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .lineLimit(2)
                    .accessibilityAddTraits(.isHeader)
                Text(ConversationStrings.text("file.sheet.message"))
                    .font(WaiveraFont.body)
                    .foregroundStyle(Palette.textSecondary)
                if isBusy {
                    Label(ConversationStrings.text("file.preparing"), systemImage: "hourglass")
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                }
                WaiveraButton(
                    ConversationStrings.text("file.save"),
                    systemImage: "square.and.arrow.down",
                    isLoading: isBusy
                ) {
                    onSave()
                }
                .disabled(isBusy)
                WaiveraButton(
                    ConversationStrings.text("file.share"),
                    variant: .secondary,
                    systemImage: "square.and.arrow.up"
                ) {
                    onShare()
                }
                .disabled(isBusy)
            }
            .padding(Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .sheet(item: preparedBinding) { file in
                switch file.purpose {
                case .share: ShareSheet(url: file.url, onFinish: onFinish)
                case .save: DocumentExporter(url: file.url, onFinish: onFinish)
                }
            }
        }

        /// Dismissing the share sheet or picker without finishing counts as cancelled.
        private var preparedBinding: Binding<PreparedFile?> {
            Binding(
                get: { preparedFile },
                set: { if $0 == nil, preparedFile != nil { onFinish(false) } }
            )
        }
    }

    /// The system share sheet for a prepared file.
    private struct ShareSheet: UIViewControllerRepresentable {
        let url: URL
        let onFinish: (Bool) -> Void

        func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            controller.completionWithItemsHandler = { _, completed, _, _ in onFinish(completed) }
            return controller
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
    }

    /// "Save to Files" through the system export picker.
    private struct DocumentExporter: UIViewControllerRepresentable {
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

            init(onFinish: @escaping (Bool) -> Void) {
                self.onFinish = onFinish
            }

            func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
                onFinish(true)
            }

            func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
                onFinish(false)
            }
        }
    }

    /// Full-screen image with pinch and double-tap zoom, 1× to 5× (03 §8).
    struct ImagePreviewView: View {
        let messageId: Int
        let title: String
        let load: @MainActor (Int) async throws -> Data
        let onClose: () -> Void

        @State private var image: UIImage?
        @State private var failed = false
        @State private var scale: CGFloat = 1
        @State private var settledScale: CGFloat = 1

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Palette.scrim.ignoresSafeArea()
                content
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                        .background(Palette.scrim, in: Circle())
                }
                .padding(Spacing.medium)
                .accessibilityLabel(ConversationStrings.text("image.close"))
            }
            .task(id: messageId) {
                do {
                    image = UIImage(data: try await load(messageId))
                    failed = image == nil
                } catch {
                    failed = true
                }
            }
        }

        @ViewBuilder private var content: some View {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .scaleEffect(scale)
                    .gesture(zoom)
                    .onTapGesture(count: 2) {
                        scale = scale > 1 ? 1 : ChatMetrics.doubleTapZoom
                        settledScale = scale
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(title)
                    .accessibilityHint(ConversationStrings.text("image.zoom.hint"))
            } else if failed {
                AttachmentNotice(text: ConversationStrings.text("image.unavailable"), systemImage: "photo")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ProgressView().tint(Palette.onAccent).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        private var zoom: some Gesture {
            MagnifyGesture()
                .onChanged { value in
                    scale = min(max(settledScale * value.magnification, 1), ChatMetrics.maxZoom)
                }
                .onEnded { _ in settledScale = scale }
        }
    }
#endif
