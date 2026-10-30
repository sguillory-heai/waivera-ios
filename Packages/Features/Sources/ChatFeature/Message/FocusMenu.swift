#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// The six quick reactions in one pill. The emoji keep their size at any text size (wave 28
    /// B2), so they never fill their 48pt targets at the largest sizes.
    struct FocusReactionPill: View {
        let onReact: @MainActor (String) -> Void

        var body: some View {
            HStack(spacing: ChatMetrics.focusPillGap) {
                ForEach(ReactionRules.quick, id: \.self) { emoji in
                    Button {
                        onReact(emoji)
                    } label: {
                        Text(emoji)
                            .font(
                                .custom(FontWeightToken.regular.postScriptName, fixedSize: ChatMetrics.focusEmojiGlyph)
                            )
                            .frame(width: ChatMetrics.emojiTarget, height: ChatMetrics.emojiTarget)
                            .contentShape(RoundedRectangle(cornerRadius: Radius.tile, style: .continuous))
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityLabel(ConversationStrings.format("react.with", emoji))
                }
            }
            .padding(ChatMetrics.focusPillPadding)
            .background(Palette.raised, in: Capsule())
            .overlay(Capsule().strokeBorder(Palette.border, lineWidth: Spacing.hairline))
            .shadow(
                color: Palette.buttonRaise,
                radius: Elevation.shadow(for: Elevation.overlay).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.overlay).y
            )
            .accessibilityElement(children: .contain)
        }
    }

    /// Reply in thread, Copy text, Edit message and Bookmark, then Delete message under a hairline
    /// in the danger colour. Copy turns into a popped check reading "Copied". Taller than the room
    /// left (the largest text on a small phone), it scrolls so Delete is still reachable.
    struct FocusMenu: View {
        let model: MessageActionsModel
        let actions: MessageFocusActions

        var body: some View {
            ViewThatFits(in: .vertical) {
                rows
                ScrollView(.vertical) { rows }
                    .scrollBounceBehavior(.basedOnSize)
            }
            .background(Palette.raised, in: RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
                    .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous))
            .shadow(
                color: Palette.buttonRaise,
                radius: Elevation.shadow(for: Elevation.overlay).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.overlay).y
            )
            .accessibilityElement(children: .contain)
            .accessibilityLabel(ConversationStrings.text("open.actions"))
        }

        private var rows: some View {
            let bookmarked = model.message.isBookmarked == true
            return VStack(spacing: 0) {
                if model.canReply {
                    FocusMenuRow("action.reply", "arrowshape.turn.up.left", action: actions.onReply)
                }
                if model.canCopy {
                    FocusMenuRow(
                        model.copied ? "action.copied" : "action.copy",
                        model.copied ? "checkmark" : "doc.on.doc",
                        tone: model.copied ? .accent : .plain,
                        action: actions.onCopy
                    )
                }
                if model.canEdit {
                    FocusMenuRow("action.edit", "pencil", action: actions.onEdit)
                }
                FocusMenuRow(
                    bookmarked ? "action.bookmarked" : "action.bookmark",
                    bookmarked ? "bookmark.fill" : "bookmark",
                    tone: bookmarked ? .accent : .plain,
                    action: actions.onBookmark
                )
                if model.canDelete {
                    Rectangle()
                        .fill(Palette.border)
                        .frame(height: Spacing.hairline)
                        .padding(.vertical, Spacing.extraSmall)
                        .accessibilityHidden(true)
                    FocusMenuRow("action.delete", "trash", tone: .danger, action: actions.onDelete)
                }
            }
            .padding(.vertical, Spacing.extraSmall)
        }
    }

    /// One menu row: at least a 44pt target, a violet glyph (danger for Delete) and its label,
    /// which wraps at the largest text instead of being cut.
    private struct FocusMenuRow: View {
        enum Tone { case plain, accent, danger }

        let titleKey: String
        let systemImage: String
        let tone: Tone
        let action: @MainActor () -> Void

        init(_ titleKey: String, _ systemImage: String, tone: Tone = .plain, action: @escaping @MainActor () -> Void) {
            self.titleKey = titleKey
            self.systemImage = systemImage
            self.tone = tone
            self.action = action
        }

        var body: some View {
            Button {
                action()
            } label: {
                HStack(spacing: Spacing.mediumSmall) {
                    Image(systemName: systemImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: ControlSize.iconTileSmallGlyph, height: ControlSize.iconTileSmallGlyph)
                        .foregroundStyle(tone == .danger ? Palette.dangerText : Palette.accent)
                        .popOnChange(of: systemImage)
                        .accessibilityHidden(true)
                    Text(ConversationStrings.text(titleKey))
                        .waiveraTextStyle(.bodyLarge)
                        .foregroundStyle(textColor)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.vertical, Spacing.extraSmall + Spacing.xxSmall)
                .frame(maxWidth: .infinity, minHeight: ControlSize.minHitTarget, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.row))
        }

        private var textColor: Color {
            switch tone {
            case .plain: Palette.text
            case .accent: Palette.accent
            case .danger: Palette.dangerText
            }
        }
    }
#endif
