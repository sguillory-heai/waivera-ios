#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One Needs you row. Every row deep-links to its exact target through `onOpen`.
    struct NeedsYouRow: View {
        let item: NeedsYouItem
        let formatter: TodayFormatter
        let onOpen: (TodayDestination, Int64?) -> Void
        let onRespond: (String, Bool) -> Void

        var body: some View {
            switch item {
            case .directMessage(let message): directMessage(message)
            case .mention(let mention): self.mention(mention)
            case .invitation(let invitation):
                InvitationRow(item: invitation, formatter: formatter, onOpen: onOpen, onRespond: onRespond)
            case .ticket(let ticket): self.ticket(ticket)
            }
        }

        private func directMessage(_ item: DirectMessageItem) -> some View {
            let name = item.name ?? TodayStrings.text("today.dm.fallbackName")
            let snippet = TodayStrings.snippet(item.snippet)
            return TodayRow(
                headline: name,
                supporting: TodayStrings.joined(snippet, item.when.map(formatter.past)),
                emphasized: true,
                accessibilityText: TodayStrings.spoken(
                    name,
                    TodayStrings.unreadMessages(item.unreadCount),
                    snippet,
                    item.when.map(formatter.pastSpoken)
                ),
                accessibilityHintText: TodayStrings.text("today.hint.openConversation"),
                action: { onOpen(.chat(.conversation(id: item.conversationId, targetMessageId: nil)), nil) },
                leading: { AvatarView(name: name, size: ControlSize.iconTile) },
                trailing: { CountBadge(count: item.unreadCount) }
            )
        }

        private func mention(_ item: MentionItem) -> some View {
            let summary = TodayStrings.summary(item.summary)
            let kind = TodayStrings.text("today.kind.mention")
            return TodayRow(
                headline: summary,
                supporting: TodayStrings.joined(kind, item.when.map(formatter.past)),
                emphasized: true,
                accessibilityText: TodayStrings.format(
                    "today.activity.unreadPrefix",
                    TodayStrings.spoken(kind, summary, item.when.map(formatter.pastSpoken))
                ),
                accessibilityHintText: TodayStrings.text("today.hint.openMessage"),
                action: { onOpen(.chat(item.destination), item.activityId) },
                leading: { IconTile(systemImage: "at") },
                trailing: { UnreadDot(accessibilityLabel: TodayStrings.text("today.activity.unread")) }
            )
        }

        private func ticket(_ item: TicketItem) -> some View {
            let title =
                item.ticketNumber.map { TodayStrings.format("today.ticket.numbered", $0) }
                ?? TodayStrings.text("today.ticket.title")
            let detail = item.ticketTitle ?? TodayStrings.snippet(item.snippet)
            return TodayRow(
                eyebrow: item.ticketNumber == nil ? nil : TodayStrings.text("today.ticket.title"),
                eyebrowTint: Palette.accent,
                headline: title,
                supporting: TodayStrings.joined(detail, item.when.map(formatter.past)),
                emphasized: true,
                accessibilityText: TodayStrings.spoken(
                    title,
                    TodayStrings.unreadMessages(item.unreadCount),
                    detail,
                    item.when.map(formatter.pastSpoken)
                ),
                accessibilityHintText: TodayStrings.text("today.hint.openConversation"),
                action: { onOpen(.chat(.conversation(id: item.conversationId, targetMessageId: nil)), nil) },
                leading: { IconTile(systemImage: "ticket") },
                trailing: { CountBadge(count: item.unreadCount) }
            )
        }
    }

    /// A pending invitation with one-tap answers. The body opens the event; Decline and Accept
    /// are separate 48pt buttons so VoiceOver reaches each on its own.
    private struct InvitationRow: View {
        let item: InvitationItem
        let formatter: TodayFormatter
        let onOpen: (TodayDestination, Int64?) -> Void
        let onRespond: (String, Bool) -> Void

        var body: some View {
            let title = item.title ?? TodayStrings.text("today.invitation.untitled")
            let eyebrow = TodayStrings.text("today.invitation.label")
            let time = item.time.map(formatter.upcoming)
            let organizer = item.organizer.map { TodayStrings.format("today.invitation.from", $0) }
            let details = time.map { TodayStrings.joined($0, organizer) } ?? organizer
            VStack(alignment: .leading, spacing: 0) {
                TodayRow(
                    eyebrow: eyebrow,
                    eyebrowTint: Palette.accent,
                    headline: title,
                    supporting: details,
                    emphasized: true,
                    accessibilityText: TodayStrings.spoken(eyebrow, title, details),
                    accessibilityHintText: TodayStrings.text("today.hint.openEvent"),
                    action: { onOpen(.event(id: item.eventId), nil) },
                    leading: { IconTile(systemImage: "calendar.badge.clock") }
                )
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: Spacing.small) { answerButtons(title: title) }
                    VStack(spacing: Spacing.small) { answerButtons(title: title) }
                }
                .padding(.leading, Spacing.medium + ControlSize.iconTile + Spacing.smallPlus)
                .padding(.trailing, Spacing.medium)
                .padding(.bottom, Spacing.smallPlus)
                .background(Palette.accentWash)
            }
        }

        @ViewBuilder private func answerButtons(title: String) -> some View {
            WaiveraButton(TodayStrings.text("today.invitation.decline"), variant: .secondary) {
                onRespond(item.eventId, false)
            }
            .accessibilityHint(Text(TodayStrings.format("today.invitation.decline.label", title)))
            WaiveraButton(TodayStrings.text("today.invitation.accept")) {
                onRespond(item.eventId, true)
            }
            .accessibilityHint(Text(TodayStrings.format("today.invitation.accept.label", title)))
        }
    }
#endif
