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

    /// An unconfirmed send: Sending…, Waiting for connection…, or Failed with Retry, Edit and
    /// Discard (03 §11).
    struct PendingRowView: View {
        let row: PendingRow
        let actions: MessageRowActions

        private var outgoing: OutgoingMessage { row.outgoing }
        private var isFailed: Bool {
            if case .failed = outgoing.state { return true }
            return false
        }

        var body: some View {
            VStack(alignment: .trailing, spacing: Spacing.extraSmall) {
                if !outgoing.text.isEmpty {
                    PlainMessageText(text: outgoing.text)
                        .padding(.horizontal, Spacing.smallPlus)
                        .padding(.vertical, Spacing.small)
                        .background(
                            Palette.accentSoft,
                            in: BubbleShape.make(
                                isMine: true,
                                previous: row.groupedWithPrevious,
                                next: row.groupedWithNext
                            )
                        )
                        .opacity(isFailed ? Emphasis.pressed : 1)
                }
                if outgoing.attachment != nil {
                    Label(
                        ConversationStrings.text(isFailed ? "upload.failed" : "uploading"),
                        systemImage: isFailed ? "exclamationmark.circle" : "arrow.up.circle"
                    )
                    .font(WaiveraFont.caption)
                    .foregroundStyle(isFailed ? Palette.danger : Palette.textSecondary)
                }
                Text(statusText)
                    .font(WaiveraFont.caption)
                    .foregroundStyle(isFailed ? Palette.danger : Palette.textSecondary)
                if isFailed { failedActions }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.leading, Spacing.huge)
            .padding(.horizontal, Spacing.medium)
            .padding(.top, row.groupedWithPrevious ? Spacing.hairline : Spacing.small)
            .accessibilityElement(children: .contain)
        }

        private var statusText: String {
            switch outgoing.state {
            case .sending: ConversationStrings.text("sending")
            case .queued: ConversationStrings.text("queued")
            case .failed: ConversationStrings.text("failed")
            }
        }

        private var failedActions: some View {
            HStack(spacing: Spacing.extraSmall) {
                WaiveraButton(ConversationStrings.text("failed.retry"), variant: .plain) {
                    actions.retry(outgoing.clientMessageId)
                }
                if outgoing.attachment == nil, let editFailed = actions.editFailed {
                    WaiveraButton(ConversationStrings.text("failed.edit"), variant: .plain) { editFailed(outgoing) }
                }
                WaiveraButton(ConversationStrings.text("failed.discard"), variant: .plain) {
                    actions.discard(outgoing.clientMessageId)
                }
            }
            .fixedSize()
        }
    }
#endif
