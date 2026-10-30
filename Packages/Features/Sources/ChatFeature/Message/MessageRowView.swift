#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One message: avatar and name for others, the bubble, reactions, the thread chip and the
    /// time line (03 §4-6). A live arrival comes in per `BubbleArrival`: my own pops on the send
    /// spring, someone else's glides up on the layout spring. History and Reduce Motion arrive
    /// at rest.
    struct MessageRowView: View {
        let row: MessageRow
        let context: RowContext
        let actions: MessageRowActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var arrival: Double = 1

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
            .modifier(BubbleArrivalEffect(progress: arrival, mine: row.isMine))
            .waiveraAnimation(.state, value: isHighlighted)
            .onAppear(perform: animateArrival)
        }

        private func animateArrival() {
            guard row.isLiveArrival, !reduceMotion else { return }
            arrival = 0
            let curve = row.isMine ? MotionPolicy.sendPop(reduceMotion: false) : .spring(MotionSpec.defaultSpatial)
            withAnimation(Motion.animation(curve)) { arrival = 1 }
        }
    }

    /// Draws an arrival's progress as a `BubbleArrival` frame: my own bubble grows from its
    /// bottom trailing corner, everyone's rises from `BubbleArrival.offset` below and fades in.
    struct BubbleArrivalEffect: ViewModifier, Animatable {
        var progress: Double
        let mine: Bool

        var animatableData: Double {
            get { progress }
            set { progress = newValue }
        }

        func body(content: Content) -> some View {
            let frame = BubbleArrival.frame(progress: progress, mine: mine)
            content
                .scaleEffect(frame.scale, anchor: mine ? .bottomTrailing : .bottomLeading)
                .offset(y: frame.offsetFraction * BubbleArrival.offset)
                .opacity(frame.alpha)
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
                    // The bot is Waivera itself, so it wears the mark (UI8-08); the author line names it.
                    LogoTile(size: ControlSize.avatarSmall)
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
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(ConversationStrings.format("open.profile", name))
                } else {
                    AvatarView(name: name, size: ControlSize.avatarSmall)
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
                OneLineName(name, style: .labelSmall)
                    .foregroundStyle(isBot ? Palette.accent : Palette.text)
                    .layoutPriority(1)
                if isBot {
                    StatusBadge(ConversationStrings.text("automated"), tone: .accent)
                }
            }
            .padding(.bottom, Spacing.xxSmall)
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
            AvatarView(name: name, image: image, size: size)
                .task(id: userId) {
                    guard let data = await loader(userId), let decoded = UIImage(data: data) else { return }
                    image = Image(uiImage: decoded)
                }
                .accessibilityHidden(true)
        }
    }
#endif
