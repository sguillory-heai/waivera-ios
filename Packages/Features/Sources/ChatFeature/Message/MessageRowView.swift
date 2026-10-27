#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One message: avatar and name for others, the bubble, reactions, the thread chip and the
    /// tap-to-show timestamp (03 §4-6). A live arrival slides and fades in; history stays still.
    struct MessageRowView: View {
        let row: MessageRow
        let context: RowContext
        let actions: MessageRowActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var arrived = true

        private var message: ChatMessage { row.message }
        private var isHighlighted: Bool { context.highlightKey == row.key }

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.small) {
                if row.isMine {
                    Spacer(minLength: Spacing.huge)
                } else {
                    AuthorAvatar(row: row, name: context.authorName(message), actions: actions)
                }
                VStack(alignment: row.isMine ? .trailing : .leading, spacing: Spacing.extraSmall) {
                    if !row.isMine, !row.groupedWithPrevious {
                        AuthorLine(name: context.authorName(message), isBot: row.isBot)
                    }
                    MessageBubble(row: row, context: context, actions: actions)
                    MessageFooter(row: row, context: context)
                }
                .frame(maxWidth: .infinity, alignment: row.isMine ? .trailing : .leading)
                if !row.isMine, !row.isBot {
                    Spacer(minLength: Spacing.large)
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.top, row.groupedWithPrevious ? Spacing.hairline : Spacing.small)
            .padding(.bottom, row.isBot ? Spacing.small : Spacing.hairline)
            .background(isHighlighted ? Palette.accentWash : Color.clear)
            .overlay {
                if isHighlighted {
                    Rectangle().strokeBorder(Palette.accentBorderStrong, lineWidth: Spacing.hairline)
                }
            }
            .offset(y: arrived ? 0 : ChatMetrics.arrivalOffset)
            .opacity(arrived ? 1 : ChatMetrics.arrivalMinOpacity)
            .waiveraAnimation(.state, value: isHighlighted)
            .onAppear(perform: animateArrival)
        }

        private func animateArrival() {
            guard row.isLiveArrival, !reduceMotion else { return }
            arrived = false
            withAnimation(Motion.animation(.layout, reduceMotion: reduceMotion)) { arrived = true }
        }
    }

    private struct AuthorAvatar: View {
        let row: MessageRow
        let name: String
        let actions: MessageRowActions

        var body: some View {
            Group {
                if row.groupedWithPrevious {
                    Color.clear.frame(width: ControlSize.avatarSmall, height: ControlSize.avatarSmall)
                } else if row.isBot {
                    Image(systemName: "sparkles")
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.accent)
                        .frame(width: ControlSize.avatarSmall, height: ControlSize.avatarSmall)
                        .background(Palette.accentWash, in: Circle())
                        .overlay(Circle().strokeBorder(Palette.accentBorderStrong, lineWidth: Spacing.hairline))
                        .accessibilityHidden(true)
                } else if let authorId = row.message.authorId ?? row.message.author?.id {
                    Button {
                        actions.openPerson(authorId)
                    } label: {
                        ChatAvatar(
                            userId: authorId,
                            name: name,
                            size: ControlSize.avatarSmall,
                            loader: actions.loadAvatar
                        )
                        .frame(minWidth: ControlSize.minHitTarget, minHeight: ControlSize.minHitTarget, alignment: .top)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.pressScale)
                    .accessibilityLabel(ConversationStrings.format("open.profile", name))
                } else {
                    AvatarView(name: name, size: ControlSize.avatarSmall, rounded: true)
                        .accessibilityHidden(true)
                }
            }
            .padding(.top, row.groupedWithPrevious ? 0 : ChatMetrics.avatarTopOffset)
        }
    }

    private struct AuthorLine: View {
        let name: String
        let isBot: Bool

        var body: some View {
            HStack(spacing: Spacing.extraSmall) {
                Text(name)
                    .font(WaiveraFont.label)
                    .foregroundStyle(isBot ? Palette.accent : Palette.text)
                    .lineLimit(2)
                if isBot {
                    StatusBadge(ConversationStrings.text("automated"), tone: .accent)
                }
            }
            .accessibilityHidden(true)
        }
    }

    /// An avatar image loaded through the data layer, initials until it arrives.
    struct ChatAvatar: View {
        let userId: String
        let name: String
        let size: CGFloat
        let loader: @MainActor (String) async -> Data?

        @State private var image: Image?

        var body: some View {
            AvatarView(name: name, image: image, size: size, rounded: true)
                .task(id: userId) {
                    guard let data = await loader(userId), let decoded = UIImage(data: data) else { return }
                    image = Image(uiImage: decoded)
                }
                .accessibilityHidden(true)
        }
    }
#endif
