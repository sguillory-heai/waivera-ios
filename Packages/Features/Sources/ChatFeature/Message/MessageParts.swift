#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Reaction pills: tap toggles, long press shows who reacted (03 §15).
    struct ReactionPills: View {
        let row: MessageRow
        let actions: MessageRowActions

        var body: some View {
            // Wraps like a flow layout without a custom Layout: rows of pills that fit.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.extraSmall) { pills }
                VStack(alignment: row.isMine ? .trailing : .leading, spacing: Spacing.extraSmall) { pills }
            }
        }

        @ViewBuilder private var pills: some View {
            ForEach(row.reactions) { reaction in
                ReactionPill(reaction: reaction, messageId: row.message.id, actions: actions)
            }
        }
    }

    private struct ReactionPill: View {
        let reaction: ReactionSummary
        let messageId: Int
        let actions: MessageRowActions

        var body: some View {
            let content = HStack(spacing: Spacing.extraSmall) {
                Text(reaction.emoji).font(WaiveraFont.caption)
                if reaction.showsCount {
                    Text("\(reaction.count)")
                        .font(WaiveraFont.badge)
                        .foregroundStyle(reaction.mine ? Palette.accent : Palette.textSecondary)
                }
            }
            .padding(.horizontal, Spacing.small)
            .frame(minHeight: ChatMetrics.reactionPillHeight)
            .background(reaction.mine ? Palette.accentSoft : Palette.background, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    reaction.mine ? Palette.accentBorderStrong : Palette.border,
                    lineWidth: Spacing.hairline
                )
            )
            .frame(minHeight: ControlSize.minHitTarget)
            .contentShape(Rectangle())

            if let react = actions.react {
                content
                    .onTapGesture { react(messageId, reaction.emoji) }
                    .onLongPressGesture { actions.reactionDetails?(messageId, reaction.emoji) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ConversationStrings.reactionLabel(reaction))
                    .accessibilityAddTraits(reaction.mine ? [.isButton, .isSelected] : .isButton)
                    .accessibilityHint(ConversationStrings.text("reaction.toggle"))
                    .accessibilityAction(named: ConversationStrings.text("reaction.details")) {
                        actions.reactionDetails?(messageId, reaction.emoji)
                    }
            } else {
                content
                    .onLongPressGesture { actions.reactionDetails?(messageId, reaction.emoji) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ConversationStrings.reactionLabel(reaction))
            }
        }
    }

    /// Image, file, scanning or blocked attachment (03 §8). Images load through the data
    /// layer's authenticated loader; a pending upload shows its progress.
    struct AttachmentView: View {
        let message: ChatMessage
        let attachment: Attachment
        let actions: MessageRowActions

        var body: some View {
            switch attachment.scanStatus {
            case .rejected:
                AttachmentNotice(
                    text: ConversationStrings.text("attachment.blocked"),
                    systemImage: "exclamationmark.shield"
                )
            case .pending:
                AttachmentNotice(text: ConversationStrings.text("attachment.scanning"), systemImage: "hourglass")
            default:
                if AttachmentRules.isImage(attachment) {
                    ImageAttachment(message: message, actions: actions)
                } else {
                    FileAttachment(message: message, attachment: attachment) { actions.openAttachment(message) }
                }
            }
        }
    }

    private struct ImageAttachment: View {
        let message: ChatMessage
        let actions: MessageRowActions

        @State private var image: UIImage?
        @State private var failed = false

        var body: some View {
            Group {
                if let image {
                    Button {
                        actions.openAttachment(message)
                    } label: {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: ChatMetrics.imageWidth, height: ChatMetrics.imageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: ChatMetrics.imageRadius, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: ChatMetrics.imageRadius, style: .continuous)
                                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                            )
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(WaiveraFont.caption)
                                    .foregroundStyle(Palette.onAccent)
                                    .padding(Spacing.extraSmall)
                                    .background(Palette.scrim, in: RoundedRectangle(cornerRadius: Radius.chip))
                                    .padding(Spacing.small)
                            }
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityLabel(ConversationStrings.text("open.image"))
                } else if failed {
                    AttachmentNotice(text: ConversationStrings.text("image.unavailable"), systemImage: "photo")
                } else {
                    SkeletonBlock(
                        width: ChatMetrics.imageWidth,
                        height: ChatMetrics.imageHeight,
                        cornerRadius: ChatMetrics.imageRadius
                    )
                }
            }
            .task(id: message.id) { await load() }
        }

        private func load() async {
            guard image == nil else { return }
            do {
                let data = try await actions.loadImage(message.id)
                let size = CGSize(
                    width: ChatMetrics.imageWidth * ChatMetrics.decodeScale,
                    height: ChatMetrics.imageHeight * ChatMetrics.decodeScale
                )
                image = UIImage(data: data)?.preparingThumbnail(of: size) ?? UIImage(data: data)
                failed = image == nil
            } catch is CancellationError {
                return
            } catch {
                failed = true
            }
        }
    }

    private struct FileAttachment: View {
        let message: ChatMessage
        let attachment: Attachment
        let onOpen: () -> Void

        var body: some View {
            let kind = AttachmentRules.kind(attachment, messageId: message.id)
            Button(action: onOpen) {
                HStack(spacing: Spacing.small) {
                    Image(systemName: kind.systemImage)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.accent)
                        .frame(width: ControlSize.iconTile, height: ControlSize.iconTile)
                        .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.chip))
                    VStack(alignment: .leading, spacing: Spacing.hairline) {
                        Text(AttachmentRules.fileName(attachment, messageId: message.id))
                            .font(WaiveraFont.subtitle)
                            .foregroundStyle(Palette.text)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(ConversationStrings.text("file.caption"))
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.down.circle")
                        .foregroundStyle(Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(Spacing.small)
                .frame(maxWidth: ChatMetrics.fileCardWidth)
                .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                )
            }
            .buttonStyle(.pressScale)
            .accessibilityElement(children: .combine)
        }
    }

    struct AttachmentNotice: View {
        let text: String
        let systemImage: String

        var body: some View {
            Label(text, systemImage: systemImage)
                .font(WaiveraFont.caption)
                .foregroundStyle(Palette.textSecondary)
                .padding(.horizontal, Spacing.smallPlus)
                .padding(.vertical, Spacing.small)
                .frame(maxWidth: ChatMetrics.fileCardWidth, minHeight: ControlSize.minHitTarget, alignment: .leading)
                .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }
    }
#endif
