#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

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
                List(
                    Array(ReactionRules.reactions(reactions, emoji: selected ?? "").enumerated()),
                    id: \.offset
                ) { _, reaction in
                    let name = ConversationStrings.reactorName(
                        ReactionRules.reactorName(reaction, viewerId: viewerId, names: names)
                    )
                    HStack(spacing: Spacing.smallPlus) {
                        AvatarView(name: name, size: ControlSize.avatarSmall)
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
