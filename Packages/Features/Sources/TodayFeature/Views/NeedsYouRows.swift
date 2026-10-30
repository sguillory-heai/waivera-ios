#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// One Needs you card. Every card deep-links to its exact target through `onOpen`.
    struct NeedsYouRow: View {
        let item: NeedsYouItem
        let formatter: TodayFormatter
        let onOpen: (TodayDestination, Int64?) -> Void
        let onRespond: (String, Bool) -> Void

        var body: some View {
            switch item {
            case .notSent(let notSent): self.notSent(notSent)
            case .directMessage(let message): directMessage(message)
            case .mention(let mention): self.mention(mention)
            case .invitation(let invitation):
                InvitationRow(item: invitation, formatter: formatter, onOpen: onOpen, onRespond: onRespond)
            case .ticket(let ticket): self.ticket(ticket)
            }
        }

        /// A message of mine that never went out leads: only I can fix it.
        private func notSent(_ item: NotSentItem) -> some View {
            let eyebrow = TodayStrings.text("today.notSent")
            let headline = TodayStrings.format("today.notSent.headline", item.name)
            let supporting = TodayStrings.text("today.notSent.supporting")
            return TodayRow(
                eyebrow: eyebrow,
                eyebrowTint: Palette.dangerText,
                headline: headline,
                supporting: supporting,
                emphasized: true,
                accessibilityText: TodayStrings.format("today.notSent.label", eyebrow, headline, supporting),
                accessibilityHintText: TodayStrings.text("today.notSent.hint"),
                action: { onOpen(.chat(.conversation(id: item.conversationId, targetMessageId: nil)), nil) },
                leading: { TodayTile(systemImage: "exclamationmark.circle", tone: .danger) }
            )
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
                leading: { AvatarView(name: name, size: ControlSize.cardTile) },
                trailing: { CountBadge(count: item.unreadCount) }
            )
        }

        /// Who mentioned the person as the headline, then what they said as a quote behind a rose
        /// rule. A single mention has no count: bold text and "Unread" are signal enough.
        private func mention(_ item: MentionItem) -> some View {
            let summary = TodayStrings.summary(item.summary)
            let parts = QuotedSummary.of(summary)
            let kind = TodayStrings.text("today.kind.mention")
            let rose = TileTone.rose.contentColor
            return TodayRow(
                eyebrow: TodayStrings.joined(kind, item.when.map(formatter.past)),
                eyebrowTint: rose,
                headline: TodayStrings.mentionHeadline(lead: parts.lead, actor: item.actorName),
                quote: parts.quote,
                quoteRuleTint: rose,
                emphasized: true,
                accessibilityText: TodayStrings.format(
                    "today.activity.unreadPrefix",
                    TodayStrings.spoken(kind, summary, item.when.map(formatter.pastSpoken))
                ),
                accessibilityHintText: TodayStrings.text("today.hint.openMessage"),
                action: { onOpen(.chat(item.destination), item.activityId) },
                leading: { TodayTile(systemImage: "at", tone: .rose) }
            )
        }

        /// The age leads the supporting line: the ticket key is one long word, so at large text
        /// it would push the age past the ellipsis (UI3-11). The key never breaks at its hyphen.
        private func ticket(_ item: TicketItem) -> some View {
            let title = item.ticketTitle ?? TodayStrings.text("today.ticket.title")
            let spokenKey = item.ticketNumber.map { TodayStrings.format("today.ticket.numbered", $0) }
            let shownKey = item.ticketNumber.map {
                TodayStrings.format("today.ticket.numbered", TodayStrings.nonBreakingHyphens($0))
            }
            let snippet = TodayStrings.snippet(item.snippet)
            let shown = shownKey ?? snippet
            return TodayRow(
                headline: title,
                supporting: item.when.map { TodayStrings.joined(formatter.past($0), shown) } ?? shown,
                emphasized: true,
                accessibilityText: TodayStrings.spoken(
                    title,
                    TodayStrings.unreadMessages(item.unreadCount),
                    spokenKey ?? snippet,
                    item.when.map(formatter.pastSpoken)
                ),
                accessibilityHintText: TodayStrings.text("today.hint.openConversation"),
                action: { onOpen(.chat(.conversation(id: item.conversationId, targetMessageId: nil)), nil) },
                leading: { TodayTile(systemImage: "ticket", tone: .amber) },
                trailing: { CountBadge(count: item.unreadCount) }
            )
        }
    }

    /// A pending invitation with one-tap answers. The body opens the event; Decline (tonal) and
    /// Accept (primary) are separate buttons inside the card so VoiceOver reaches each on its own.
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
            TodayRow(
                eyebrow: eyebrow,
                eyebrowTint: TileTone.brand.contentColor,
                headline: title,
                supporting: details,
                emphasized: true,
                showsChevron: false,
                accessibilityText: TodayStrings.spoken(eyebrow, title, details),
                accessibilityHintText: TodayStrings.text("today.hint.openEvent"),
                action: { onOpen(.event(id: item.eventId), nil) },
                leading: { TodayTile(systemImage: "calendar", tone: .brand) },
                trailing: { EmptyView() },
                below: {
                    HStack(spacing: Spacing.small) {
                        WaiveraButton(TodayStrings.text("today.invitation.decline"), variant: .tonal, fillsWidth: true)
                        {
                            onRespond(item.eventId, false)
                        }
                        .accessibilityLabel(Text(TodayStrings.format("today.invitation.decline.label", title)))
                        WaiveraButton(TodayStrings.text("today.invitation.accept"), fillsWidth: true) {
                            onRespond(item.eventId, true)
                        }
                        .accessibilityLabel(Text(TodayStrings.format("today.invitation.accept.label", title)))
                    }
                    .padding(.bottom, TodayCard.padding)
                }
            )
        }
    }

    #if DEBUG
        private struct NeedsYouGallery: View {
            let state: TodayState

            var body: some View {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(state.needsYou.items) { item in
                            NeedsYouRow(
                                item: item,
                                formatter: TodayFormatting.shared,
                                onOpen: { _, _ in },
                                onRespond: { _, _ in }
                            )
                        }
                    }
                }
                .background(Palette.background)
            }
        }

        #Preview("Light") { NeedsYouGallery(state: TodayPreviewStates.populated()) }
        #Preview("Dark") { NeedsYouGallery(state: TodayPreviewStates.populated()).preferredColorScheme(.dark) }
        #Preview("AX5, long content") {
            NeedsYouGallery(state: TodayPreviewStates.longContent()).dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
