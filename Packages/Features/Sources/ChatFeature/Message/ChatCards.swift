#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A ticket update from the Waivera bot (03 §20): badges, title, id, Open and the dates.
    struct TicketCardView: View {
        let ticket: TicketCard
        let onOpen: @MainActor (URL) -> Void

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        private var notification: TicketNotification { ticket.notification }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                // The badges wrap, so a long type never pushes CRITICAL off the card (wave 28 B4).
                BadgeFlowLayout(spacing: Spacing.extraSmall) {
                    StatusBadge(notification.type, tone: .accent)
                    StatusBadge(notification.priority, tone: tone)
                }
                Text(notification.title)
                    .waiveraTextStyle(.titleMedium)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(notification.ticketId)
                    .waiveraTextStyle(.bodySmall)
                    .foregroundStyle(Palette.textSecondary)
                WaiveraButton(
                    ConversationStrings.text("ticket.open"),
                    variant: .secondary,
                    systemImage: "arrow.up.right.square"
                ) {
                    onOpen(notification.url)
                }
                VStack(spacing: 0) {
                    meta(
                        "person",
                        "ticket.created.by",
                        notification.createdBy ?? ConversationStrings.text("ticket.unknown.user")
                    )
                    Rectangle().fill(Palette.border).frame(height: Spacing.hairline)
                    meta("calendar", "ticket.created", Self.text(ticket.created), muted: ticket.created == .notSet)
                    Rectangle().fill(Palette.border).frame(height: Spacing.hairline)
                    meta("calendar.badge.clock", "ticket.due", Self.text(ticket.due), muted: ticket.due == .notSet)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                        .strokeBorder(Palette.border, lineWidth: Spacing.hairline)
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private var tone: BadgeTone {
            switch ticket.tone {
            case .critical: .danger
            case .high, .medium: .warning
            case .other: .neutral
            }
        }

        /// The label keeps its one-line width and the value wraps in the room it leaves, or the
        /// row stacks when that room is under half the row, or at large text (wave 28 B3).
        private func meta(_ icon: String, _ labelKey: String, _ value: String, muted: Bool = false) -> some View {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Image(systemName: icon)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                TicketMetaLayout(gap: Spacing.medium, stacks: dynamicTypeSize.isLargeText) {
                    Text(ConversationStrings.text(labelKey))
                        .foregroundStyle(Palette.textSecondary)
                    Text(value)
                        .foregroundStyle(muted ? Palette.textSecondary : Palette.text)
                        .multilineTextAlignment(dynamicTypeSize.isLargeText ? .leading : .trailing)
                }
            }
            .waiveraTextStyle(.bodySmall)
            .padding(.horizontal, Spacing.smallPlus)
            .padding(.vertical, Spacing.small)
            .accessibilityElement(children: .combine)
        }

        static func text(_ date: TicketDate) -> String {
            switch date {
            case .notSet: ConversationStrings.text("ticket.not.set")
            case .onDate(let day): ChatTime.shortDate(day, showYear: true)
            case .raw(let value): value
            }
        }
    }

    /// A ticket meta row's label and value (`TicketMetaFit`): side by side with the label at its
    /// one-line width and the value end-aligned in the room left, else stacked.
    struct TicketMetaLayout: Layout {
        var gap: CGFloat
        var stacks: Bool

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let parts = arrange(width: proposal.width, subviews: subviews)
            return parts.size
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            guard subviews.count == 2 else { return }
            let parts = arrange(width: bounds.width, subviews: subviews)
            subviews[0].place(
                at: CGPoint(x: bounds.minX, y: bounds.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(parts.label)
            )
            let valueX = parts.stacked ? bounds.minX : bounds.maxX - parts.value.width
            let valueY = parts.stacked ? bounds.minY + parts.label.height + Spacing.xxSmall : bounds.minY
            subviews[1].place(
                at: CGPoint(x: valueX, y: valueY),
                anchor: .topLeading,
                proposal: ProposedViewSize(parts.value)
            )
        }

        /// The pair's size, each part's size and whether the value sits under the label.
        private struct Arrangement {
            var size: CGSize
            var label: CGSize
            var value: CGSize
            var stacked: Bool
        }

        private func arrange(width: CGFloat?, subviews: Subviews) -> Arrangement {
            guard subviews.count == 2 else {
                return Arrangement(size: .zero, label: .zero, value: .zero, stacked: false)
            }
            let label = subviews[0].sizeThatFits(.unspecified)
            let valueIdeal = subviews[1].sizeThatFits(.unspecified)
            let pair = width ?? (label.width + gap + valueIdeal.width)
            let room =
                stacks
                ? nil
                : TicketMetaFit.valueMaxWidth(
                    pairWidth: pair,
                    gap: gap,
                    labelWidth: label.width,
                    valueWidth: valueIdeal.width
                )
            if let room {
                let value = subviews[1].sizeThatFits(ProposedViewSize(width: room, height: nil))
                let fitted = CGSize(width: min(value.width, room), height: value.height)
                let size = CGSize(width: pair, height: max(label.height, fitted.height))
                return Arrangement(size: size, label: label, value: fitted, stacked: false)
            }
            let stackedLabel = subviews[0].sizeThatFits(ProposedViewSize(width: pair, height: nil))
            let value = subviews[1].sizeThatFits(ProposedViewSize(width: pair, height: nil))
            let fitted = CGSize(width: min(value.width, pair), height: value.height)
            let height = stackedLabel.height + Spacing.xxSmall + fitted.height
            let size = CGSize(width: pair, height: height)
            return Arrangement(size: size, label: stackedLabel, value: fitted, stacked: true)
        }
    }

    /// Badges in rows that wrap: each keeps its own width (cut to the row when longer).
    struct BadgeFlowLayout: Layout {
        var spacing: CGFloat

        func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
            let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
            let width = rows.map { $0.width }.max() ?? 0
            let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(0, rows.count - 1))
            return CGSize(width: proposal.width ?? width, height: height)
        }

        func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
            var y = bounds.minY
            for row in arrange(width: bounds.width, subviews: subviews) {
                var x = bounds.minX
                for (index, size) in row.items {
                    subviews[index].place(
                        at: CGPoint(x: x, y: y),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(size)
                    )
                    x += size.width + spacing
                }
                y += row.height + spacing
            }
        }

        private struct Row {
            var items: [(Int, CGSize)] = []
            var width: CGFloat = 0
            var height: CGFloat = 0
        }

        private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
            var rows: [Row] = []
            var current = Row()
            for index in subviews.indices {
                var size = subviews[index].sizeThatFits(.unspecified)
                if size.width > width {
                    size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
                    size.width = min(size.width, width)
                }
                let needed = current.items.isEmpty ? size.width : current.width + spacing + size.width
                if needed > width, !current.items.isEmpty {
                    rows.append(current)
                    current = Row()
                }
                current.width = current.items.isEmpty ? size.width : current.width + spacing + size.width
                current.height = max(current.height, size.height)
                current.items.append((index, size))
            }
            if !current.items.isEmpty { rows.append(current) }
            return rows
        }
    }

    /// Every system line of one call, collapsed into a card that expands to the details (11 §7).
    struct CallLogCard: View {
        let row: CallLogRow
        let zone: TimeZone
        let isHighlighted: Bool

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isExpanded = false

        private var summary: CallLogSummary { row.summary }

        var body: some View {
            VStack(spacing: 0) {
                Button {
                    withAnimation(Motion.animation(.layout, reduceMotion: reduceMotion)) { isExpanded.toggle() }
                } label: {
                    header
                }
                .buttonStyle(.pressScale)
                .accessibilityHint(ConversationStrings.text(isExpanded ? "call.collapse" : "call.expand"))
                if isExpanded {
                    Rectangle().fill(Palette.border).frame(height: Spacing.hairline)
                    details
                }
            }
            .background(isHighlighted ? Palette.accentWash : Palette.surface, in: shape)
            .overlay(
                shape.strokeBorder(
                    isHighlighted ? Palette.accentBorderStrong : Palette.border,
                    lineWidth: Spacing.hairline
                )
            )
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.extraSmall)
        }

        private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: Radius.card, style: .continuous) }

        private var header: some View {
            HStack(spacing: Spacing.small) {
                IconTile(
                    systemImage: summary.isMissed ? "phone.down.fill" : "video.fill",
                    tone: summary.isMissed ? .danger : .brand
                )
                VStack(alignment: .leading, spacing: Spacing.hairline) {
                    Text(ConversationStrings.callTitle(summary.outcome))
                        .font(WaiveraFont.subtitle)
                        .foregroundStyle(Palette.text)
                    if let duration = summary.duration {
                        Text(duration).font(WaiveraFont.caption).foregroundStyle(Palette.textSecondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let time = summary.time {
                    Text(ChatTime.clock(time, zone: zone)).font(WaiveraFont.caption).foregroundStyle(
                        Palette.textSecondary
                    )
                }
                Image(systemName: "chevron.down")
                    .foregroundStyle(Palette.textSecondary)
                    .rotationEffect(.degrees(isExpanded ? ChatMetrics.halfTurnDegrees : 0))
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Spacing.smallPlus)
            .padding(.vertical, Spacing.small)
            .frame(minHeight: ControlSize.minHitTarget)
            .contentShape(Rectangle())
        }

        private var details: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                ForEach(row.messages, id: \.id) { message in
                    let parsed = SystemMessages.parse(CallLogs.text(of: message))
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                        Text(parsed.text)
                            .font(WaiveraFont.caption)
                            .foregroundStyle(Palette.text)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        if let time = parsed.embeddedTimestamp ?? message.createdAt {
                            Text(ChatTime.clock(time, zone: zone))
                                .font(WaiveraFont.caption)
                                .foregroundStyle(Palette.textSecondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(.horizontal, Spacing.smallPlus)
            .padding(.vertical, Spacing.small)
        }
    }
#endif
