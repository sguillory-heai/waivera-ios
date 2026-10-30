#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One timeline item, dispatched to its row view.
    struct TimelineItemView: View {
        let item: TimelineItem
        let context: RowContext
        let actions: MessageRowActions

        var body: some View {
            switch item {
            case .day(_, let day):
                DaySeparatorView(day: day, today: ChatTime.day(context.now, zone: context.zone))
            case .message(let row):
                MessageRowView(row: row, context: context, actions: actions)
            case .pending(let row):
                PendingRowView(row: row, actions: actions)
            case .system(let row):
                SystemRowView(text: row.text)
            case .callLog(let row):
                CallLogCard(row: row, zone: context.zone, isHighlighted: context.highlightKey == row.key)
            }
        }
    }

    struct SystemRowView: View {
        let text: String

        var body: some View {
            Text(text)
                .font(WaiveraFont.caption.italic())
                .foregroundStyle(Palette.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.large)
                .padding(.vertical, Spacing.small)
        }
    }

    struct DaySeparatorView: View {
        let day: ChatDay
        let today: ChatDay

        var body: some View {
            HStack(spacing: Spacing.smallPlus) {
                divider
                Text(ConversationStrings.day(DayLabel.of(day, today: today)))
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.textSecondary)
                divider
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.smallPlus)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }

        private var divider: some View {
            Rectangle().fill(Palette.border).frame(height: Spacing.hairline).accessibilityHidden(true)
        }
    }

    /// My unconfirmed send (Android `Footer`, `PendingMeta`). The bubble pops in on the send
    /// spring while its row grows to its height, pushing the conversation up (landing grow).
    /// The line under it stays quiet for the first beat, so a good connection never flashes
    /// "Sending…"; then "Sending…" fades in. A failure shows "Not sent" at once with Retry in
    /// sight, and Edit and Discard beside it (behind More at large text). The model plays the
    /// one failure haptic; this view is silent.
    struct PendingRowView: View {
        let row: PendingRow
        let actions: MessageRowActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var sendingLabelDue = false
        @State private var arrival: Double = 1
        @State private var grown: Double = 1

        private var outgoing: OutgoingMessage { row.outgoing }
        private var phase: PendingFooterPhase {
            PendingFooterPhase(outgoing.state, sendingLabelDue: sendingLabelDue)
        }

        var body: some View {
            LandingGrowLayout(fraction: grown) {
                VStack(alignment: .trailing, spacing: Spacing.extraSmall) {
                    bubble
                        .modifier(BubbleArrivalEffect(progress: arrival, mine: true))
                    PendingFooterLine(phase: phase, outgoing: outgoing, actions: actions)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, Spacing.huge)
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, row.groupedWithPrevious ? Spacing.hairline : Spacing.small)
            }
            .clipped()
            .accessibilityElement(children: .contain)
            .onAppear(perform: land)
            .task(id: row.key) {
                try? await Task.sleep(for: .seconds(PendingFooterPhase.sendingLabelDelay))
                guard !Task.isCancelled else { return }
                withAnimation(Motion.animation(MotionPolicy.swapEnter(reduceMotion: reduceMotion))) {
                    sendingLabelDue = true
                }
            }
        }

        @ViewBuilder private var bubble: some View {
            if !outgoing.text.isEmpty {
                PlainMessageText(text: outgoing.text)
                    .padding(.horizontal, Spacing.mediumSmall - Spacing.hairline)
                    .padding(.vertical, Spacing.small)
                    .frame(minWidth: ChatMetrics.bubbleMinWidth, alignment: .trailing)
                    .background(
                        Palette.myBubble,
                        in: BubbleShape.make(isMine: true, previous: row.groupedWithPrevious, next: row.groupedWithNext)
                    )
                    .accessibilityLabel(ConversationStrings.rowLabel(author: nil, isMine: true, body: outgoing.text))
            }
            if outgoing.attachment != nil {
                Label(
                    ConversationStrings.text(phase == .failed ? "upload.failed" : "uploading"),
                    systemImage: phase == .failed ? "exclamationmark.circle" : "arrow.up.circle"
                )
                .waiveraTextStyle(.labelMedium)
                .foregroundStyle(phase == .failed ? Palette.dangerText : Palette.textSecondary)
            }
        }

        /// A live send lands: its row grows on the layout spring and the bubble pops on the send
        /// spring. History and Reduce Motion are simply there.
        private func land() {
            guard row.isLiveArrival, !reduceMotion else { return }
            grown = 0
            arrival = 0
            withAnimation(Motion.animation(.layout, reduceMotion: false)) { grown = 1 }
            withAnimation(Motion.animation(MotionPolicy.sendPop(reduceMotion: false))) { arrival = 1 }
        }
    }

    /// The line under a pending bubble. The quiet slot keeps the line's height, so nothing jumps
    /// when "Sending…" arrives.
    private struct PendingFooterLine: View {
        let phase: PendingFooterPhase
        let outgoing: OutgoingMessage
        let actions: MessageRowActions

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            VStack(alignment: .trailing, spacing: Spacing.extraSmall) {
                Text(ConversationStrings.text(phase.copyKey ?? "sending"))
                    .waiveraTextStyle(.labelMedium)
                    .foregroundStyle(phase == .failed ? Palette.dangerText : Palette.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .opacity(phase == .quiet ? 0 : 1)
                    .accessibilityHidden(phase == .quiet)
                if phase == .failed {
                    if dynamicTypeSize.isLargeText {
                        compactActions
                    } else {
                        fullActions
                    }
                }
            }
            .padding(.top, Spacing.xxSmall)
            .waiveraAnimation(.state, value: phase)
        }

        /// Discard, Edit and Retry, end-aligned on one line.
        private var fullActions: some View {
            HStack(spacing: Spacing.extraSmall) {
                WaiveraButton(ConversationStrings.text("failed.discard"), variant: .text, size: .compact) {
                    actions.discard(outgoing.clientMessageId)
                }
                if outgoing.attachment == nil, let editFailed = actions.editFailed {
                    WaiveraButton(ConversationStrings.text("failed.edit"), variant: .text, size: .compact) {
                        editFailed(outgoing)
                    }
                }
                retry
            }
            .fixedSize()
        }

        /// At large text the three would wrap, so Retry stays and Edit and Discard move behind More.
        private var compactActions: some View {
            HStack(spacing: Spacing.extraSmall) {
                retry
                Menu {
                    if outgoing.attachment == nil, let editFailed = actions.editFailed {
                        Button(ConversationStrings.text("failed.edit")) { editFailed(outgoing) }
                    }
                    Button(ConversationStrings.text("failed.discard"), role: .destructive) {
                        actions.discard(outgoing.clientMessageId)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .foregroundStyle(Palette.accent)
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.press(.compact))
                .accessibilityLabel(ConversationStrings.text("failed.more"))
            }
        }

        private var retry: some View {
            WaiveraButton(
                ConversationStrings.text("failed.retry"),
                variant: .tonal,
                size: .compact,
                systemImage: "arrow.clockwise"
            ) {
                actions.retry(outgoing.clientMessageId)
            }
        }
    }

    /// A row that lands with my own send grows from no height to its own, on the animation that
    /// changes `fraction`, so the rows above are pushed up instead of jumping (Android M2-01).
    /// The content sits at the bottom and is clipped while it grows.
    struct LandingGrowLayout: Layout {
        var fraction: Double

        var animatableData: Double {
            get { fraction }
            set { fraction = newValue }
        }

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let size = subviews.first?.sizeThatFits(proposal) ?? .zero
            return CGSize(width: size.width, height: size.height * min(1, max(0, fraction)))
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            guard let content = subviews.first else { return }
            let size = content.sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
            content.place(
                at: CGPoint(x: bounds.minX, y: bounds.maxY - size.height),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: bounds.width, height: size.height)
            )
        }
    }
#endif
