#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The bubble: body, attachment, reactions and the thread chip. Tap shows the time, a long
    /// press opens the actions (03 §6, §14).
    struct MessageBubble: View {
        let row: MessageRow
        let context: RowContext
        let actions: MessageRowActions

        private var message: ChatMessage { row.message }
        private var hasBody: Bool { message.isDeleted || row.ticket != nil || message.hasBody }
        private var shape: UnevenRoundedRectangle {
            BubbleShape.make(isMine: row.isMine, previous: row.groupedWithPrevious, next: row.groupedWithNext)
        }

        var body: some View {
            VStack(alignment: row.isMine ? .trailing : .leading, spacing: Spacing.small) {
                BubbleBody(row: row, actions: actions)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(accessibilityLabel)
                    .accessibilityHint(ConversationStrings.text("show.time"))
                    .accessibilityAction { actions.toggleTimestamp(row.key) }
                    .accessibilityAction(named: ConversationStrings.text("open.actions")) { openActions() }
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
            .padding(.horizontal, hasBody ? Spacing.smallPlus : 0)
            .padding(.vertical, hasBody ? Spacing.small : 0)
            .frame(minWidth: hasBody ? ChatMetrics.bubbleMinWidth : nil, alignment: row.isMine ? .trailing : .leading)
            .background(fill, in: shape)
            .overlay {
                if hasBody { shape.stroke(border, lineWidth: Spacing.hairline) }
            }
            .contentShape(shape)
            .onTapGesture { actions.toggleTimestamp(row.key) }
            .onLongPressGesture { openActions() }
        }

        private var fill: Color {
            guard hasBody else { return .clear }
            return row.isMine && !row.isBot ? Palette.accentSoft : Palette.surface
        }

        private var border: Color {
            row.isBot || row.isMine ? Palette.accentBorder : Palette.border
        }

        private func openActions() {
            guard !message.isDeleted, let longPress = actions.longPress else { return }
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

    /// "Saved" and the relative time with "edited" (03 §4).
    struct MessageFooter: View {
        let row: MessageRow
        let context: RowContext

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var savedScale: CGFloat = 1

        var body: some View {
            let message = row.message
            let showsTime = context.visibleTimestamps.contains(row.key) && message.createdAt != nil
            if showsTime || message.isBookmarked == true {
                HStack(spacing: Spacing.small) {
                    if showsTime, let createdAt = message.createdAt {
                        let relative = ConversationStrings.relative(
                            ChatTime.relative(createdAt, now: context.now, zone: context.zone)
                        )
                        Text(message.isEdited ? ConversationStrings.format("timestamp.edited", relative) : relative)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    if message.isBookmarked == true {
                        StatusBadge(ConversationStrings.text("saved"), tone: .accent, systemImage: "bookmark.fill")
                            .scaleEffect(savedScale)
                            .onAppear(perform: pop)
                    }
                }
                .padding(.top, Spacing.extraSmall)
            }
        }

        private func pop() {
            guard !reduceMotion else { return }
            savedScale = ChatMetrics.savedPopStart
            withAnimation(Motion.animation(.celebrate, reduceMotion: reduceMotion)) { savedScale = 1 }
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
