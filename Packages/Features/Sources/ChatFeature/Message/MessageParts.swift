#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The engagement row under a bubble, as on the web and Android (`MessageEngagementRow`):
    /// reaction chips first, then "N replies", side by side and wrapping onto more lines from the
    /// bubble's own side. Every chip is a soft rounded square sized from its text, so it grows
    /// evenly with Dynamic Type. A reaction chip toggles mine on tap and shows who reacted on long
    /// press; read-only, it is inert. Each one says its emoji, count and whether I reacted, never
    /// colour alone.
    struct MessageEngagementRow: View {
        let row: MessageRow
        let actions: MessageRowActions

        private var message: ChatMessage { row.message }
        private var openThread: (@MainActor (ChatMessage) -> Void)? { Self.openThread(row, actions: actions) }

        /// "N replies" shows only on a thread root with replies, where the screen can open threads.
        private static func openThread(
            _ row: MessageRow,
            actions: MessageRowActions
        ) -> (@MainActor (ChatMessage) -> Void)? {
            guard !row.message.isThreadReply, row.message.threadReplyCount > 0 else { return nil }
            return actions.openThread
        }

        /// Whether the row has anything to show, so an empty one takes no space.
        static func isVisible(_ row: MessageRow, actions: MessageRowActions) -> Bool {
            !row.reactions.isEmpty || openThread(row, actions: actions) != nil
        }

        var body: some View {
            ReactionFlowLayout(spacing: ChatMetrics.engagementGap, alignEnd: row.isMine) {
                ForEach(row.reactions) { reaction in
                    ReactionChip(reaction: reaction, messageId: message.id, actions: actions)
                }
                if let openThread {
                    RepliesChip(count: message.threadReplyCount) { openThread(message) }
                }
            }
            .padding(.top, ChatMetrics.engagementTop)
        }
    }

    /// Rows of chips that wrap like Android's `FlowRow`, packed to the leading or trailing edge.
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

    /// The inside of every engagement chip: padded from its text, on the chip shape. The 44pt
    /// touch target grows outside the layout (`ChipHitShape`), so it never pushes the row away
    /// from the bubble.
    private struct EngagementChipBody<Content: View>: View {
        let fill: Color
        let outline: Color
        let outlineWidth: CGFloat
        @ViewBuilder let content: Content

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.chip, style: .continuous) }

        var body: some View {
            HStack(spacing: Spacing.extraSmall) { content }
                .padding(.horizontal, ChatMetrics.engagementChipPaddingX)
                .padding(.vertical, ChatMetrics.engagementChipPaddingY)
                .background(fill, in: shape)
                .overlay(shape.strokeBorder(outline, lineWidth: outlineWidth))
                .contentShape(ChipHitShape())
        }
    }

    /// A chip's touch area: at least 44pt tall, but never reaching up into the bubble (it stops
    /// at the gap above the row) or sideways into the next chip, so it grows downward instead.
    private struct ChipHitShape: Shape {
        func path(in rect: CGRect) -> Path {
            let top = min(ChatMetrics.engagementTop, max(ControlSize.minHitTarget - rect.height, 0))
            let height = max(rect.height + top, ControlSize.minHitTarget)
            let side = ChatMetrics.engagementGap / 2
            return Path(CGRect(x: rect.minX - side, y: rect.minY - top, width: rect.width + 2 * side, height: height))
        }
    }

    /// One reaction (Android `ReactionChip`): mine on the soft accent with an accent outline,
    /// others on the surface with a hairline. The count always shows, 1 included. Adding or
    /// taking back a reaction, or someone else's landing, pops the chip.
    private struct ReactionChip: View {
        let reaction: ReactionSummary
        let messageId: Int
        let actions: MessageRowActions

        var body: some View {
            if let react = actions.react {
                chip
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
                chip
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(ConversationStrings.reactionLabel(reaction))
            }
        }

        private var chip: some View {
            EngagementChipBody(
                fill: reaction.mine ? Palette.accentSoft : Palette.surface,
                outline: reaction.mine ? Palette.accent : Palette.border,
                outlineWidth: reaction.mine ? ControlSize.selectedOutline : Spacing.hairline
            ) {
                Text(reaction.emoji).waiveraTextStyle(.bodySmall)
                Text(verbatim: "\(reaction.count)")
                    .waiveraTextStyle(.labelMedium, weight: reaction.mine ? .semibold : nil)
                    .foregroundStyle(reaction.mine ? Palette.onAccentSoft : Palette.textSecondary)
            }
            .popOnChange(of: [reaction.count, reaction.mine ? 1 : 0])
        }
    }

    /// "N replies" (Android `RepliesChip`) on the accent wash. The glyph takes its size from the
    /// label's font, so it is never taller than the text at any Dynamic Type size.
    private struct RepliesChip: View {
        let count: Int
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                EngagementChipBody(
                    fill: Palette.accentWash,
                    outline: Palette.accentBorder,
                    outlineWidth: Spacing.hairline
                ) {
                    Image(systemName: "arrowshape.turn.up.left.2")
                        .imageScale(.small)
                        .accessibilityHidden(true)
                    Text(ConversationStrings.replies(count))
                }
                .waiveraTextStyle(.labelMedium)
                .foregroundStyle(Palette.accent)
            }
            .buttonStyle(.pressScale)
            .accessibilityHint(ConversationStrings.text("open.thread"))
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
