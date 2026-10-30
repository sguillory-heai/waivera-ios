#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The bubble: body, attachment, reactions and the thread chip. A tap opens its time line;
    /// a long press sinks it and opens the focus overlay over it (spec §9.1). Silent.
    struct MessageBubble: View {
        let row: MessageRow
        let context: RowContext
        let actions: MessageRowActions

        @State private var anchor = AnchorBox()

        private var message: ChatMessage { row.message }
        private var hasBody: Bool { message.isDeleted || row.ticket != nil || message.hasBody }
        /// My own messages wear the soft violet (plum in dark) with the theme's ink (v5 decision
        /// 3B); a deleted one stays quiet whoever wrote it.
        private var tinted: Bool { hasBody && row.isMine && !row.isBot && !message.isDeleted }
        private var canOpenActions: Bool { actions.longPress != nil && !message.isDeleted }
        private var shape: UnevenRoundedRectangle {
            BubbleShape.make(isMine: row.isMine, previous: row.groupedWithPrevious, next: row.groupedWithNext)
        }

        var body: some View {
            if canOpenActions {
                bubble
                    .waiveraPressable(
                        depth: .button,
                        longPressActionName: ConversationStrings.text("open.actions"),
                        onTap: { actions.toggleTimestamp(row.key) },
                        onLongPress: openActions
                    )
            } else {
                bubble
                    .contentShape(shape)
                    .onTapGesture { actions.toggleTimestamp(row.key) }
                    .accessibilityAction { actions.toggleTimestamp(row.key) }
            }
        }

        private var bubble: some View {
            VStack(alignment: row.isMine ? .trailing : .leading, spacing: Spacing.extraSmall + Spacing.xxSmall) {
                BubbleBody(row: row, actions: actions)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(ConversationStrings.text("show.time"))
                if let attachment = message.attachment, !message.isDeleted {
                    AttachmentView(message: message, attachment: attachment, actions: actions)
                }
                if !row.reactions.isEmpty {
                    ReactionPills(row: row, actions: actions)
                }
                if let openThread = actions.openThread, !message.isThreadReply, message.threadReplyCount > 0 {
                    ThreadChip(count: message.threadReplyCount) { openThread(message) }
                }
            }
            .padding(.horizontal, hasBody ? Spacing.mediumSmall - Spacing.hairline : 0)
            .padding(.vertical, hasBody ? Spacing.small : 0)
            .frame(minWidth: hasBody ? ChatMetrics.bubbleMinWidth : nil, alignment: row.isMine ? .trailing : .leading)
            .background(fill, in: shape)
            .overlay {
                if hasBody && !tinted { shape.strokeBorder(border, lineWidth: Spacing.hairline) }
            }
            .contentShape(shape)
            .background {
                GeometryReader { proxy in
                    let box = anchor
                    Color.clear.onChange(of: proxy.frame(in: .global), initial: true) { _, frame in
                        box.frame = frame
                    }
                }
            }
        }

        private var fill: Color {
            guard hasBody else { return .clear }
            return tinted ? Palette.myBubble : Palette.surface
        }

        private var border: Color {
            row.isBot || row.isMine ? Palette.accentBorder : Palette.border
        }

        private func openActions() {
            guard canOpenActions, let longPress = actions.longPress else { return }
            actions.recordAnchor(message.id, anchor.frame)
            longPress(message)
        }

        private var accessibilityLabel: String {
            let body: String
            if message.isDeleted {
                body = ConversationStrings.text("message.deleted")
            } else if let ticket = row.ticket {
                body = ticket.notification.title
            } else if !message.copyableText.isEmpty {
                body = message.copyableText
            } else if let attachment = message.attachment {
                body = ConversationStrings.format(
                    "row.attachment",
                    AttachmentRules.fileName(attachment, messageId: message.id)
                )
            } else {
                body = ""
            }
            let label = ConversationStrings.rowLabel(
                author: context.authorName(message),
                isMine: row.isMine,
                body: body
            )
            guard let createdAt = message.createdAt else { return label }
            return label + ", " + ChatTime.clock(createdAt, zone: context.zone)
        }
    }

    /// Bubble corners tighten on the author's side next to a grouped neighbour.
    enum BubbleShape {
        static func make(isMine: Bool, previous: Bool, next: Bool) -> UnevenRoundedRectangle {
            let full = ChatMetrics.bubbleRadius
            let tight = ChatMetrics.bubbleGroupedRadius
            let top = previous ? tight : full
            let bottom = next ? tight : full
            let radii =
                isMine
                ? RectangleCornerRadii(topLeading: full, bottomLeading: full, bottomTrailing: bottom, topTrailing: top)
                : RectangleCornerRadii(topLeading: top, bottomLeading: bottom, bottomTrailing: full, topTrailing: full)
            return UnevenRoundedRectangle(cornerRadii: radii, style: .continuous)
        }
    }

    private struct BubbleBody: View {
        let row: MessageRow
        let actions: MessageRowActions

        var body: some View {
            let message = row.message
            if message.isDeleted {
                Text(ConversationStrings.text("message.deleted"))
                    .font(WaiveraFont.body.italic())
                    .foregroundStyle(Palette.textSecondary)
            } else if let ticket = row.ticket {
                TicketCardView(ticket: ticket, onOpen: actions.openTicket)
            } else if let rich = row.rich {
                RichTextView(document: rich)
            } else if message.hasBody {
                PlainMessageText(text: message.copyableText)
            }
        }
    }

    /// Under the bubble (Android `SettledFooter`). The last bubble of a run always shows its
    /// clock ("9:41 AM", or "Sent · 9:41 AM" under my own), which is how a send or a retry
    /// confirms, silently. A bubble inside a run opens its time line on tap, as a relative time;
    /// the line grows and folds on the layout spring so the list moves instead of jumping.
    struct MessageFooter: View {
        let row: MessageRow
        let context: RowContext

        private var message: ChatMessage { row.message }
        private var bookmarked: Bool { message.isBookmarked == true }
        private var endOfRun: Bool { !row.groupedWithNext && !message.isDeleted }

        var body: some View {
            let label = Self.label(row, context: context)
            if endOfRun || message.createdAt == nil {
                if label != nil || bookmarked { FooterLine(label: label, bookmarked: bookmarked) }
            } else {
                Expand(isExpanded: label != nil || bookmarked) {
                    FooterLine(label: label, bookmarked: bookmarked)
                }
            }
        }

        static func label(_ row: MessageRow, context: RowContext) -> String? {
            let message = row.message
            guard let createdAt = message.createdAt else { return nil }
            let endOfRun = !row.groupedWithNext && !message.isDeleted
            let text: String
            if endOfRun {
                let clock = ChatTime.clock(createdAt, zone: context.zone)
                text = row.isMine ? ConversationStrings.format("sent.at", clock) : clock
            } else if context.visibleTimestamps.contains(row.key) {
                text = ConversationStrings.relative(ChatTime.relative(createdAt, now: context.now, zone: context.zone))
            } else {
                return nil
            }
            return message.isEdited ? ConversationStrings.format("timestamp.edited", text) : text
        }
    }

    /// The time line and the "Saved" pill, which pops in when a message is bookmarked.
    private struct FooterLine: View {
        let label: String?
        let bookmarked: Bool

        var body: some View {
            HStack(spacing: Spacing.small) {
                if let label {
                    Text(label)
                        .waiveraTextStyle(.labelMedium)
                        .foregroundStyle(Palette.textSecondary)
                }
                PopVisibility(isVisible: bookmarked) {
                    StatusBadge(ConversationStrings.text("saved"), tone: .accent, systemImage: "bookmark.fill")
                }
            }
            .padding(.top, Spacing.extraSmall)
        }
    }

    struct ThreadChip: View {
        let count: Int
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                Label(ConversationStrings.replies(count), systemImage: "arrowshape.turn.up.left.2")
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.accent)
                    .padding(.horizontal, Spacing.small)
                    .padding(.vertical, Spacing.extraSmall)
                    .background(Palette.accentWash, in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous))
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
            .accessibilityHint(ConversationStrings.text("open.thread"))
        }
    }
#endif
