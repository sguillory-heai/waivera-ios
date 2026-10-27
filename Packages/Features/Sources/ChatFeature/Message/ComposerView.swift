#if canImport(UIKit)
    import PhotosUI
    import SwiftUI
    import UniformTypeIdentifiers
    import WaiveraDesign

    /// What the composer shows; the screens fill it from their state.
    struct ComposerConfig {
        var placeholderKey = "composer.placeholder"
        var sendLabelKey = "send"
        var allowsImages = true
        var isEnabled = false
        var canSend = false
        var isUploading = false
        var isEditing = false
        var stagedImage: StagedImage?
        var focusRequest = 0
    }

    /// The bottom composer, inset into the safe area so the keyboard pushes it up without manual
    /// offsets. Images go through the system photo picker and are staged until sent (03 §11).
    struct ComposerView: View {
        @Binding var draft: String
        let config: ComposerConfig
        var onDraftChanged: () -> Void = {}
        var onSend: () -> Void = {}
        var onCancelEdit: () -> Void = {}
        var onStageImage: (StagedImage) -> Void = { _ in }
        var onRemoveImage: () -> Void = {}
        var onImageUnreadable: () -> Void = {}

        @FocusState private var isFocused: Bool
        @State private var pickedItem: PhotosPickerItem?

        var body: some View {
            VStack(spacing: Spacing.small) {
                if config.isEditing { editBar }
                if let image = config.stagedImage { StagedImageCard(image: image, onRemove: onRemoveImage) }
                HStack(alignment: .bottom, spacing: Spacing.small) {
                    if config.allowsImages, !config.isEditing { attachButton }
                    TextField(ConversationStrings.text(config.placeholderKey), text: $draft, axis: .vertical)
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.text)
                        .lineLimit(1...ChatMetrics.composerMaxLines)
                        .focused($isFocused)
                        .disabled(!config.isEnabled)
                        .padding(.horizontal, Spacing.smallPlus)
                        .padding(.vertical, Spacing.small)
                        .frame(minHeight: ControlSize.minHitTarget)
                        .background(
                            Palette.surfaceMuted,
                            in: RoundedRectangle(cornerRadius: Radius.pill, style: .continuous)
                        )
                        .onChange(of: draft) { onDraftChanged() }
                        .accessibilityIdentifier("composer.field")
                    sendButton
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .background(Palette.background)
            .overlay(alignment: .top) { Rectangle().fill(Palette.border).frame(height: Spacing.hairline) }
            .onChange(of: config.focusRequest) { isFocused = true }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                pickedItem = nil
                Task { await stage(item) }
            }
        }

        private var attachButton: some View {
            PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(Palette.accent)
                    .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
            }
            .disabled(!config.isEnabled || config.isUploading)
            .accessibilityLabel(ConversationStrings.text("attach.image"))
        }

        private var sendButton: some View {
            Button(action: onSend) {
                Group {
                    if config.isUploading {
                        ProgressView().tint(Palette.onAccent)
                    } else {
                        Image(systemName: config.isEditing ? "checkmark" : "arrow.up")
                            .font(WaiveraFont.bodyEmphasis)
                            .foregroundStyle(Palette.onAccent)
                    }
                }
                .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                .background(config.canSend ? Palette.accent : Palette.accentBorder, in: Circle())
            }
            .buttonStyle(.pressScale)
            .disabled(!config.canSend)
            .accessibilityLabel(ConversationStrings.text(config.isEditing ? "save.edit" : config.sendLabelKey))
            .accessibilityIdentifier("composer.send")
        }

        private var editBar: some View {
            HStack(spacing: Spacing.small) {
                Label(ConversationStrings.text("editing"), systemImage: "pencil")
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCancelEdit) {
                    Image(systemName: "xmark")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                }
                .accessibilityLabel(ConversationStrings.text("cancel.edit"))
            }
        }

        private func stage(_ item: PhotosPickerItem) async {
            guard let data = try? await item.loadTransferable(type: Data.self), UIImage(data: data) != nil else {
                onImageUnreadable()
                return
            }
            let type = item.supportedContentTypes.first { $0.conforms(to: .image) }
            let mimeType = type?.preferredMIMEType ?? "image/jpeg"
            let fileName = "image." + (type?.preferredFilenameExtension ?? "jpg")
            onStageImage(StagedImage(data: data, fileName: fileName, mimeType: mimeType))
        }
    }

    private struct StagedImageCard: View {
        let image: StagedImage
        let onRemove: () -> Void

        @State private var preview: UIImage?

        var body: some View {
            HStack(spacing: Spacing.smallPlus) {
                if let preview {
                    Image(uiImage: preview)
                        .resizable()
                        .scaledToFill()
                        .frame(width: ChatMetrics.stagedThumbnail, height: ChatMetrics.stagedThumbnail)
                        .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                        .accessibilityHidden(true)
                }
                Text(ConversationStrings.text("selected.image"))
                    .font(WaiveraFont.subtitle)
                    .foregroundStyle(Palette.text)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WaiveraButton(ConversationStrings.text("remove.image"), variant: .plain, action: onRemove)
                    .fixedSize()
            }
            .padding(Spacing.small)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .task(id: image.data.count) {
                let size = CGSize(
                    width: ChatMetrics.stagedThumbnail * ChatMetrics.decodeScale,
                    height: ChatMetrics.stagedThumbnail * ChatMetrics.decodeScale
                )
                preview = UIImage(data: image.data)?.preparingThumbnail(of: size)
            }
        }
    }
#endif
