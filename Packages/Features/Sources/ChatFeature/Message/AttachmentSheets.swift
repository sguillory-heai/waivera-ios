#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraDesign

    /// Save to Files or Open / Share for a downloaded file (03 §8; Android `FileActionsContent`):
    /// the name as the title, a line on what each does, a busy line while the file downloads, and
    /// the two actions full width, Save first.
    struct FileActionsSheet: View {
        let fileName: String
        let isBusy: Bool
        let preparedFile: PreparedFile?
        let onSave: () -> Void
        let onShare: () -> Void
        let onFinish: (_ completed: Bool) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                Text(fileName)
                    .waiveraTextStyle(.titleLarge)
                    .foregroundStyle(Palette.text)
                    .lineLimit(3)
                    .accessibilityAddTraits(.isHeader)
                Text(ConversationStrings.text("file.sheet.message"))
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.textSecondary)
                if isBusy {
                    HStack(spacing: Spacing.small) {
                        BusyIndicator()
                        Text(ConversationStrings.text("file.preparing"))
                            .waiveraTextStyle(.bodyMedium)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    .accessibilityElement(children: .combine)
                }
                WaiveraButton(
                    ConversationStrings.text("file.save"),
                    systemImage: "arrow.down.to.line",
                    fillsWidth: true,
                    action: onSave
                )
                .disabled(isBusy)
                WaiveraButton(
                    ConversationStrings.text("file.share"),
                    variant: .secondary,
                    systemImage: "square.and.arrow.up",
                    fillsWidth: true,
                    action: onShare
                )
                .disabled(isBusy)
            }
            .padding(.horizontal, Spacing.gutter)
            .padding(.top, Spacing.large)
            .padding(.bottom, Spacing.large)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface)
            .waiveraAnimation(.state, value: isBusy)
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

        func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

        func makeUIViewController(context: Context) -> UIActivityViewController {
            let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            // The handler is `@Sendable`; it captures the main-actor coordinator, not the closure.
            let coordinator = context.coordinator
            controller.completionWithItemsHandler = { _, completed, _, _ in
                MainActor.assumeIsolated { coordinator.onFinish(completed) }
            }
            return controller
        }

        func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}

        @MainActor
        final class Coordinator {
            let onFinish: (Bool) -> Void

            init(onFinish: @escaping (Bool) -> Void) {
                self.onFinish = onFinish
            }
        }
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

    /// Full-screen image with pinch and double-tap zoom, 1× to 5× (03 §8; Android
    /// `ImagePreviewDialog`), on an almost black scrim with white ink: the close button on its
    /// own dark disc, the spinner without its track, and the zoom hint at the bottom. While not
    /// zoomed, a vertical swipe closes it (`ImageDismiss`): the image follows the finger and the
    /// backdrop and chrome fade in proportion. Reduce Motion keeps the image still and fades only
    /// the backdrop.
    struct ImagePreviewView: View {
        let messageId: Int
        let title: String
        let load: @MainActor (Int) async throws -> Data
        let onClose: () -> Void

        @State private var image: UIImage?
        @State private var failed = false
        @State private var scale: CGFloat = 1
        @State private var settledScale: CGFloat = 1
        @State private var dragOffset: CGFloat = 0
        /// A pinch is in progress: a vertical drift of the fingers must not move or close the image.
        @State private var isPinching = false
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        private var fade: Double { 1 - Double(ImageDismiss.progress(offset: dragOffset)) }

        var body: some View {
            ZStack(alignment: .topTrailing) {
                Palette.previewScrim.opacity(fade).ignoresSafeArea()
                content
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.onAccent)
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .background(Palette.scrim, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.press(.compact))
                .padding(Spacing.small)
                .opacity(fade)
                .accessibilityLabel(ConversationStrings.text("image.close"))
            }
            .overlay(alignment: .bottom) {
                Text(ConversationStrings.text("image.zoom.hint"))
                    .waiveraTextStyle(.labelMedium)
                    .foregroundStyle(Palette.onAccent)
                    .padding(Spacing.medium)
                    .opacity(fade)
                    .accessibilityHidden(true)
            }
            // Clear, so the conversation shows through as the backdrop fades during a swipe.
            .presentationBackground(.clear)
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
                    .offset(y: reduceMotion ? 0 : dragOffset)
                    .gesture(zoom)
                    .simultaneousGesture(swipeToClose, including: scale > 1 ? .subviews : .all)
                    .onTapGesture(count: 2) {
                        scale = scale > 1 ? 1 : ChatMetrics.doubleTapZoom
                        settledScale = scale
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityLabel(title)
                    .accessibilityHint(ConversationStrings.text("image.zoom.hint"))
            } else if failed {
                Text(ConversationStrings.text("image.unavailable"))
                    .waiveraTextStyle(.bodyMedium)
                    .foregroundStyle(Palette.onAccent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                BusyIndicator(
                    color: Palette.onAccent,
                    trackColor: .clear,
                    size: ControlSize.progressLarge,
                    lineWidth: ControlSize.progressStrokeLarge
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }

        private var zoom: some Gesture {
            MagnifyGesture()
                .onChanged { value in
                    isPinching = true
                    scale = min(max(settledScale * value.magnification, 1), ChatMetrics.maxZoom)
                }
                .onEnded { _ in
                    isPinching = false
                    settledScale = scale
                    springBack()
                }
        }

        private var swipeToClose: some Gesture {
            DragGesture(minimumDistance: Spacing.medium)
                .onChanged { value in
                    guard scale <= 1, !isPinching else { return }
                    dragOffset = value.translation.height
                }
                .onEnded { value in
                    guard scale <= 1, !isPinching, dragOffset != 0 else { return springBack() }
                    if ImageDismiss.shouldClose(offset: dragOffset, velocity: value.velocity.height) {
                        close(towards: dragOffset)
                    } else {
                        springBack()
                    }
                }
        }

        /// Sends the image off the screen the way it was going, then closes, so an upward swipe
        /// does not end in the cover sliding down. Reduce Motion closes straight away.
        private func close(towards offset: CGFloat) {
            guard !reduceMotion else { return onClose() }
            let away = (offset < 0 ? -1 : 1) * ImageDismiss.offScreen
            withAnimation(Motion.animation(.layout, reduceMotion: false)) {
                dragOffset = away
            } completion: {
                onClose()
            }
        }

        private func springBack() {
            guard dragOffset != 0 else { return }
            withAnimation(Motion.animation(.layout, reduceMotion: reduceMotion)) { dragOffset = 0 }
        }
    }
#endif
