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

    /// The bottom composer (Android `Composer`), inset into the safe area so the keyboard pushes it
    /// up without manual offsets. The field sits on the surface at rest and on the raised step with
    /// an accent edge while typing. The editing bar and a picked image slide open above the field
    /// and fold away again. Images go through the system photo picker and are staged until sent.
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
        /// The image last staged, so its card can fold away after it is removed or sent.
        @State private var shownImage: StagedImage?

        var body: some View {
            VStack(spacing: 0) {
                Expand(isExpanded: config.isEditing) { EditingBar(onCancel: onCancelEdit) }
                Expand(isExpanded: config.stagedImage != nil) {
                    if let image = config.stagedImage ?? shownImage {
                        StagedImageCard(image: image, onRemove: onRemoveImage)
                    }
                }
                HStack(alignment: .bottom, spacing: Spacing.extraSmall) {
                    if config.allowsImages, !config.isEditing { attachButton }
                    field
                    SendButton(
                        canSend: config.canSend,
                        isUploading: config.isUploading,
                        isEditing: config.isEditing,
                        label: ConversationStrings.text(config.isEditing ? "save.edit" : config.sendLabelKey),
                        onSend: onSend
                    )
                }
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, Spacing.extraSmall)
            }
            .background(Palette.background)
            .onChange(of: config.focusRequest) { isFocused = true }
            .onChange(of: config.stagedImage) { _, image in
                if let image { shownImage = image }
            }
            .onChange(of: pickedItem) { _, item in
                guard let item else { return }
                pickedItem = nil
                Task { await stage(item) }
            }
        }

        private var field: some View {
            TextField(
                "",
                text: $draft,
                prompt: Text(ConversationStrings.text(placeholderKey)).foregroundStyle(Palette.textSecondary),
                axis: .vertical
            )
            .waiveraTextStyle(.bodyMedium)
            .foregroundStyle(Palette.text)
            .tint(Palette.accent)
            .lineLimit(1...ChatMetrics.composerMaxLines)
            .focused($isFocused)
            .disabled(!config.isEnabled)
            .padding(.horizontal, Spacing.smallPlus)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: ControlSize.iconButton)
            .background(fieldFill, in: RoundedRectangle(cornerRadius: Radius.field, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.field, style: .continuous)
                    .strokeBorder(
                        isFocused ? Palette.accent : Palette.border,
                        lineWidth: isFocused ? ControlSize.fieldBorder : Spacing.hairline
                    )
            )
            .waiveraAnimation(.state, value: isFocused)
            .onChange(of: draft) { onDraftChanged() }
            .accessibilityLabel(ConversationStrings.text(placeholderKey))
            .accessibilityIdentifier("composer.field")
        }

        private var placeholderKey: String {
            config.isEditing ? "composer.edit.placeholder" : config.placeholderKey
        }

        private var fieldFill: Color {
            if !config.isEnabled { return Palette.surfaceMuted }
            return isFocused ? Palette.raised : Palette.surface
        }

        private var attachButton: some View {
            let enabled = config.isEnabled && !config.isUploading
            return PhotosPicker(selection: $pickedItem, matching: .images) {
                Image(systemName: "photo.badge.plus")
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.medium)
                    .frame(width: ControlSize.smallIcon, height: ControlSize.smallIcon)
                    .foregroundStyle(enabled ? Palette.accent : Palette.textTertiary)
                    .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.compact))
            .disabled(!enabled)
            .accessibilityLabel(ConversationStrings.text("attach.image"))
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

    /// Send is the composer's CTA (Android `SendButton`): white on the solid accent fill at the CTA
    /// radius. With nothing to send it reads as muted with a hairline, not as a faded violet. It
    /// keeps the filled look for `MotionTiming.sendPayoffHold` after a tap, so the glyph's pop
    /// plays on the violet rather than on a control already fading to disabled. A send never
    /// vibrates: the bubble's own pop confirms it.
    private struct SendButton: View {
        let canSend: Bool
        let isUploading: Bool
        let isEditing: Bool
        let label: String
        let onSend: () -> Void

        @State private var sends = 0
        @State private var justSent = false

        private var looksEnabled: Bool { canSend || justSent }
        private var ink: Color { looksEnabled ? Palette.onAccent : Palette.textSecondary }
        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.cta, style: .continuous) }

        var body: some View {
            Button {
                justSent = true
                sends += 1
                onSend()
            } label: {
                Group {
                    if isUploading {
                        BusyIndicator(color: ink)
                    } else {
                        Image(systemName: isEditing ? "checkmark" : "arrow.up")
                            .resizable()
                            .scaledToFit()
                            .fontWeight(.bold)
                            .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                            .foregroundStyle(ink)
                            .popOnChange(of: sends)
                    }
                }
                .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                .background(looksEnabled ? Palette.accentFill : Palette.surfaceMuted, in: shape)
                .overlay {
                    if !looksEnabled { shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline) }
                }
                .waiveraAnimation(.state, value: looksEnabled)
            }
            .buttonStyle(.press(.compact))
            .disabled(!canSend)
            .task(id: sends) {
                guard justSent else { return }
                try? await Task.sleep(for: .seconds(MotionTiming.sendPayoffHold))
                guard !Task.isCancelled else { return }
                justSent = false
            }
            .accessibilityLabel(label)
            .accessibilityIdentifier("composer.send")
        }
    }

    /// "Editing message" with the accent pencil and a close button (Android `EditingBar`).
    private struct EditingBar: View {
        let onCancel: () -> Void

        var body: some View {
            HStack(spacing: Spacing.small) {
                Image(systemName: "pencil")
                    .resizable()
                    .scaledToFit()
                    .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                    .foregroundStyle(Palette.accent)
                    .accessibilityHidden(true)
                Text(ConversationStrings.text("editing"))
                    .waiveraTextStyle(.labelMedium)
                    .foregroundStyle(Palette.accent)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityLabel(ConversationStrings.text("cancel.edit"))
            }
            .padding(.leading, Spacing.gutter)
            .padding(.trailing, Spacing.extraSmall)
        }
    }

    /// The picked image above the field (Android `StagedImageCard`): a thumbnail, the file name on
    /// one line cut in the middle, and Remove, inside a hairline card one touch target tall.
    private struct StagedImageCard: View {
        let image: StagedImage
        let onRemove: () -> Void

        @State private var preview: UIImage?

        var body: some View {
            HStack(spacing: Spacing.small) {
                ZStack {
                    RoundedRectangle(cornerRadius: Radius.chip, style: .continuous).fill(Palette.surfaceMuted)
                    if let preview {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFill()
                    } else {
                        Image(systemName: "photo").foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(width: ChatMetrics.stagedThumbnail, height: ChatMetrics.stagedThumbnail)
                .clipShape(RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .accessibilityHidden(true)
                // The picker gives no real file name, only a made-up "image.jpg", so the card names it.
                Text(ConversationStrings.text("selected.image"))
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WaiveraButton(ConversationStrings.text("remove.image"), variant: .text, action: onRemove)
                    .fixedSize()
            }
            .padding([.leading, .vertical], Spacing.extraSmall)
            .frame(minHeight: ControlSize.minHitTarget)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .padding(.horizontal, Spacing.gutter)
            .padding(.vertical, Spacing.extraSmall)
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
