#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The long-press sheet: a preview, quick reactions and the message actions (03 §14).
    struct MessageActionSheet: View {
        let model: MessageActionsModel
        let onReact: (String) -> Void
        let onCopy: () -> Void
        let onReply: () -> Void
        let onEdit: () -> Void
        let onBookmark: () -> Void
        let onDelete: () -> Void
        let onClose: () -> Void

        private var message: ChatMessage { model.message }

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.medium) {
                    header
                    preview
                    if model.canReact { quickReactions }
                    actions
                }
                .padding(Spacing.medium)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Palette.surface)
        }

        private var header: some View {
            HStack {
                Text(ConversationStrings.text("preview.label"))
                    .font(WaiveraFont.eyebrow)
                    .tracking(TypographyMetrics.eyebrowTracking)
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .foregroundStyle(Palette.textSecondary)
                        .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                }
                .accessibilityLabel(ConversationStrings.text("action.close"))
            }
        }

        private var preview: some View {
            Group {
                if let rich = model.rich {
                    RichTextView(document: rich)
                } else {
                    PlainMessageText(text: message.copyableText)
                }
            }
            .lineLimit(nil)
            .frame(maxWidth: .infinity, maxHeight: ChatMetrics.previewMaxHeight, alignment: .topLeading)
            .clipped()
            .padding(Spacing.smallPlus)
            .background(Palette.surfaceMuted, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }

        private var quickReactions: some View {
            HStack(spacing: Spacing.extraSmall) {
                ForEach(ReactionRules.quick, id: \.self) { emoji in
                    Button {
                        onReact(emoji)
                    } label: {
                        Text(emoji)
                            .font(WaiveraFont.screenTitle)
                            .frame(width: ChatMetrics.emojiTarget, height: ChatMetrics.emojiTarget)
                            .background(Palette.surfaceMuted, in: Circle())
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityLabel(ConversationStrings.format("react.with", emoji))
                }
            }
            .frame(maxWidth: .infinity)
        }

        private var actions: some View {
            VStack(spacing: 0) {
                if model.canCopy {
                    row(
                        model.copied ? "action.copied" : "action.copy",
                        model.copied ? "checkmark" : "doc.on.doc",
                        action: onCopy
                    )
                }
                if model.canReply { row("action.reply", "arrowshape.turn.up.left", action: onReply) }
                if model.canEdit { row("action.edit", "pencil", action: onEdit) }
                row(
                    message.isBookmarked == true ? "action.bookmarked" : "action.bookmark",
                    message.isBookmarked == true ? "bookmark.fill" : "bookmark",
                    action: onBookmark
                )
                if model.canDelete { row("action.delete", "trash", isDestructive: true, action: onDelete) }
            }
            .background(Palette.background, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        }

        private func row(
            _ titleKey: String,
            _ systemImage: String,
            isDestructive: Bool = false,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Label(ConversationStrings.text(titleKey), systemImage: systemImage)
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(isDestructive ? Palette.danger : Palette.text)
                    .frame(maxWidth: .infinity, minHeight: ControlSize.buttonHeight, alignment: .leading)
                    .padding(.horizontal, Spacing.medium)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.pressScale)
        }
    }

    /// Who reacted, one tab per emoji (03 §15).
    struct ReactionDetailsSheet: View {
        let reactions: [Reaction]
        /// The row's precomputed summaries, one tab each.
        let summaries: [ReactionSummary]
        let initialEmoji: String
        let viewerId: String?
        let names: [String: String]
        let onClose: () -> Void

        @State private var selected: String?

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.medium) {
                HStack {
                    Text(ConversationStrings.text("reactions.title"))
                        .font(WaiveraFont.sectionTitle)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .foregroundStyle(Palette.textSecondary)
                            .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                    }
                    .accessibilityLabel(ConversationStrings.text("reactions.close"))
                }
                ScrollView(.horizontal) {
                    HStack(spacing: Spacing.small) {
                        ForEach(summaries) { summary in
                            ChipView(
                                "\(summary.emoji) \(summary.count)",
                                isSelected: summary.emoji == selected
                            ) { selected = summary.emoji }
                            .frame(minWidth: ChatMetrics.reactionTabMinWidth)
                            .accessibilityLabel(ConversationStrings.reactionLabel(summary))
                        }
                    }
                }
                .scrollIndicators(.hidden)
                List(Array(ReactionRules.reactions(reactions, emoji: selected ?? "").enumerated()), id: \.offset) {
                    _,
                    reaction in
                    let name = ConversationStrings.reactorName(
                        ReactionRules.reactorName(reaction, viewerId: viewerId, names: names)
                    )
                    HStack(spacing: Spacing.smallPlus) {
                        AvatarView(name: name, size: ControlSize.avatarSmall, rounded: true)
                            .accessibilityHidden(true)
                        Text(name).font(WaiveraFont.body).foregroundStyle(Palette.text)
                    }
                    .listRowBackground(Palette.surface)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
            .padding(Spacing.medium)
            .background(Palette.surface)
            .onAppear {
                if selected == nil { selected = ReactionRules.initialTab(requested: initialEmoji, in: summaries) }
            }
        }
    }
#endif
