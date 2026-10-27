#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// A ticket update from the Waivera bot (03 §20): badges, title, id, Open and the dates.
    struct TicketCardView: View {
        let ticket: TicketCard
        let onOpen: @MainActor (URL) -> Void

        private var notification: TicketNotification { ticket.notification }

        var body: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(spacing: Spacing.extraSmall) {
                    StatusBadge(notification.type, tone: .accent)
                    StatusBadge(notification.priority, tone: tone)
                }
                Text(notification.title)
                    .font(WaiveraFont.sectionTitle)
                    .foregroundStyle(Palette.text)
                    .accessibilityAddTraits(.isHeader)
                Text(notification.ticketId)
                    .font(WaiveraFont.caption)
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

        private func meta(_ icon: String, _ labelKey: String, _ value: String, muted: Bool = false) -> some View {
            HStack(spacing: Spacing.small) {
                Image(systemName: icon)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
                Text(ConversationStrings.text(labelKey))
                    .foregroundStyle(Palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .foregroundStyle(muted ? Palette.textSecondary : Palette.text)
                    .multilineTextAlignment(.trailing)
            }
            .font(WaiveraFont.caption)
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
                    tint: summary.isMissed ? Palette.danger : Palette.accent
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
