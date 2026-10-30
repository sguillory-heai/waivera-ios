#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Reaction pills inside the bubble (03 §13; Android `ReactionPills`): they flow onto as many
    /// lines as they need, from the bubble's own side. Tap toggles mine, long press shows who
    /// reacted. Read-only, they are inert. Each pill says its emoji, count and whether I
    /// reacted, never colour alone.
    struct ReactionPills: View {
        let row: MessageRow
        let actions: MessageRowActions

        var body: some View {
            ReactionFlowLayout(spacing: Spacing.extraSmall, alignEnd: row.isMine) {
                ForEach(row.reactions) { reaction in
                    ReactionPill(reaction: reaction, messageId: row.message.id, actions: actions)
                }
            }
        }
    }

    /// Rows of pills that wrap like Android's `FlowRow`, packed to the leading or trailing edge.
    private struct ReactionFlowLayout: Layout {
        let spacing: CGFloat
        let alignEnd: Bool

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
            let rows = arrange(subviews, maxWidth: proposal.width ?? .infinity)
            let width = rows.map(\.width).max() ?? 0
            let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
            return CGSize(width: width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
            var y = bounds.minY
            for row in arrange(subviews, maxWidth: bounds.width) {
                var x = alignEnd ? bounds.maxX - row.width : bounds.minX
                for index in row.indices {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(
                        at: CGPoint(x: x, y: y + (row.height - size.height) / 2),
                        proposal: ProposedViewSize(size)
                    )
                    x += size.width + spacing
                }
                y += row.height + spacing
            }
        }

        private struct Row {
            var indices: [Int] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        private func arrange(_ subviews: Subviews, maxWidth: CGFloat) -> [Row] {
            var rows: [Row] = []
            var current = Row()
            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                let added = current.indices.isEmpty ? size.width : current.width + spacing + size.width
                if added > maxWidth, !current.indices.isEmpty {
                    rows.append(current)
                    current = Row()
                }
                current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
                current.height = max(current.height, size.height)
                current.indices.append(index)
            }
            if !current.indices.isEmpty { rows.append(current) }
            return rows
        }
    }

    /// One pill (Android `ReactionPill`): mine on the soft accent with an accent outline, others
    /// on the page with a hairline. The count always shows, 1 included. Adding or taking back a
    /// reaction, or someone else's landing, pops the pill.
    private struct ReactionPill: View {
        let reaction: ReactionSummary
        let messageId: Int
        let actions: MessageRowActions

        var body: some View {
            if let react = actions.react {
                pill
                    .frame(minHeight: ControlSize.minHitTarget)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ConversationStrings.reactionLabel(reaction))
                    .accessibilityAddTraits(reaction.mine ? .isSelected : [])
                    .accessibilityHint(ConversationStrings.text("reaction.toggle"))
                    .waiveraPressable(
                        longPressActionName: ConversationStrings.text("reaction.details"),
                        onTap: { react(messageId, reaction.emoji) },
                        onLongPress: { actions.reactionDetails?(messageId, reaction.emoji) }
                    )
            } else {
                pill
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ConversationStrings.reactionLabel(reaction))
            }
        }

        private var pill: some View {
            HStack(spacing: Spacing.extraSmall) {
                Text(reaction.emoji).waiveraTextStyle(.bodySmall)
                Text(verbatim: "\(reaction.count)")
                    .waiveraTextStyle(.labelSmall)
                    .fontWeight(reaction.mine ? .semibold : nil)
                    .foregroundStyle(reaction.mine ? Palette.onAccentSoft : Palette.textSecondary)
            }
            .padding(.horizontal, Spacing.small)
            .frame(minHeight: ChatMetrics.reactionPillHeight)
            .background(reaction.mine ? Palette.accentSoft : Palette.background, in: Capsule())
            .overlay(
                Capsule().strokeBorder(
                    reaction.mine ? Palette.accent : Palette.border,
                    lineWidth: reaction.mine ? ControlSize.selectedOutline : Spacing.hairline
                )
            )
            .popOnChange(of: [reaction.count, reaction.mine ? 1 : 0])
        }
    }

    /// Image, file, scanning or blocked attachment (03 §8). Images load through the data
    /// layer's authenticated loader.
    struct AttachmentView: View {
        let message: ChatMessage
        let attachment: Attachment
        let actions: MessageRowActions

        var body: some View {
            switch attachment.scanStatus {
            case .rejected:
                AttachmentNotice(
                    text: ConversationStrings.text("attachment.blocked"),
                    systemImage: "exclamationmark.triangle"
                )
            case .pending:
                AttachmentNotice(text: ConversationStrings.text("attachment.scanning"), systemImage: "info.circle")
            default:
                if AttachmentRules.isImage(attachment) {
                    ImageAttachment(message: message, actions: actions)
                } else {
                    FileAttachment(message: message, attachment: attachment) { actions.openAttachment(message) }
                }
            }
        }
    }

    /// The picture, pressed like a card, with the expand glyph on a scrim chip in its corner.
    private struct ImageAttachment: View {
        let message: ChatMessage
        let actions: MessageRowActions

        @State private var image: UIImage?
        @State private var failed = false

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: ChatMetrics.imageRadius, style: .continuous)
        }

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
                            .clipShape(shape)
                            .overlay(shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline))
                            .overlay(alignment: .topTrailing) { expandBadge }
                            .contentShape(shape)
                    }
                    .buttonStyle(.press(.card))
                    .accessibilityLabel(ConversationStrings.text("open.image"))
                } else if failed {
                    AttachmentNotice(text: ConversationStrings.text("image.unavailable"), systemImage: "photo")
                } else {
                    SkeletonBlock(
                        width: ChatMetrics.imageWidth,
                        height: ChatMetrics.imageLoadingHeight,
                        cornerRadius: ChatMetrics.imageRadius
                    )
                }
            }
            .task(id: message.id) { await load() }
        }

        /// White on the dark scrim, which is the one place the white glyph reads.
        private var expandBadge: some View {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .resizable()
                .scaledToFit()
                .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                .foregroundStyle(Palette.onAccent)
                .frame(width: ChatMetrics.imageBadge, height: ChatMetrics.imageBadge)
                .background(Palette.scrim, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                .padding(Spacing.small)
                .accessibilityHidden(true)
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

    /// A file card (Android `FileAttachment`): a neutral tile, the name on one line cut in the
    /// middle so the extension stays, "Tap to open" and the download glyph. At large text the
    /// tile and glyph share a top row and the name takes the card's whole width.
    private struct FileAttachment: View {
        let message: ChatMessage
        let attachment: Attachment
        let onOpen: () -> Void

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card, style: .continuous) }

        var body: some View {
            let kind = AttachmentRules.kind(attachment, messageId: message.id)
            let name = AttachmentRules.fileName(attachment, messageId: message.id)
            Button(action: onOpen) {
                Group {
                    if dynamicTypeSize.isLargeText {
                        VStack(alignment: .leading, spacing: Spacing.small) {
                            HStack {
                                IconTile(systemImage: kind.systemImage, tone: .neutral)
                                Spacer(minLength: 0)
                                downloadGlyph
                            }
                            Text(name)
                                .waiveraTextStyle(.titleSmall)
                                .foregroundStyle(Palette.text)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        HStack(spacing: Spacing.small) {
                            IconTile(systemImage: kind.systemImage, tone: .neutral)
                            VStack(alignment: .leading, spacing: 0) {
                                Text(name)
                                    .waiveraTextStyle(.titleSmall)
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Text(ConversationStrings.text("file.caption"))
                                    .waiveraTextStyle(.labelMedium)
                                    .foregroundStyle(Palette.textSecondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            downloadGlyph
                        }
                    }
                }
                .padding(Spacing.small)
                .frame(maxWidth: ChatMetrics.fileCardWidth)
                .background(Palette.surface, in: shape)
                .overlay(shape.strokeBorder(Palette.border, lineWidth: Spacing.hairline))
                .contentShape(shape)
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(name))
            .accessibilityHint(ConversationStrings.text("file.caption"))
            .accessibilityAddTraits(.isButton)
        }

        private var downloadGlyph: some View {
            Image(systemName: "arrow.down.to.line")
                .resizable()
                .scaledToFit()
                .frame(width: ControlSize.smallIcon, height: ControlSize.smallIcon)
                .foregroundStyle(Palette.textSecondary)
                .frame(width: ControlSize.icon, height: ControlSize.icon)
                .accessibilityHidden(true)
        }
    }

    /// A blocked, scanning or unavailable attachment: a muted card with the reason (Android
    /// `AttachmentNotice`).
    struct AttachmentNotice: View {
        let text: String
        let systemImage: String

        var body: some View {
            HStack(spacing: Spacing.small) {
                Image(systemName: systemImage)
                    .resizable()
                    .scaledToFit()
                    .frame(width: ControlSize.smallIcon, height: ControlSize.smallIcon)
                    .frame(width: ControlSize.icon, height: ControlSize.icon)
                    .accessibilityHidden(true)
                Text(text).waiveraTextStyle(.bodySmall)
            }
            .foregroundStyle(Palette.textSecondary)
            .padding(.horizontal, Spacing.mediumSmall)
            .padding(.vertical, Spacing.small)
            .frame(maxWidth: ChatMetrics.fileCardWidth, minHeight: ControlSize.minHitTarget, alignment: .leading)
            .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }
#endif
