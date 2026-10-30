#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// One of the later Up next items: relative time first ("in 25 min"), then the title, the
    /// clock range and the place. Teal means schedule on every screen; a soon item's kicker is teal
    /// too, and "Happening now" is spoken.
    struct NextUpRow: View {
        let item: NextUpItem
        let formatter: TodayFormatter
        let onOpen: () -> Void

        var body: some View {
            let title = item.title ?? TodayStrings.text("today.invitation.untitled")
            let time = formatter.upcoming(item.time)
            let place = item.location ?? (item.isOnline ? TodayStrings.text("today.online") : nil)
            let supporting = formatter.range(item).map { TodayStrings.joined($0, place) } ?? place
            TodayRow(
                eyebrow: time,
                eyebrowTint: item.isSoon ? TileTone.teal.contentColor : Palette.textSecondary,
                headline: title,
                supporting: supporting,
                emphasized: item.isHappeningNow,
                accessibilityText: TodayStrings.spoken(
                    time,
                    title,
                    supporting,
                    item.isHappeningNow ? TodayStrings.text("today.nextUp.happeningNow") : nil
                ),
                accessibilityHintText: TodayStrings.text("today.hint.openEvent"),
                action: onOpen,
                leading: { TodayTile(systemImage: "clock", tone: .teal) }
            )
        }
    }

    /// The first Up next item as the large card: the place tile, the title and place, a countdown
    /// chip while it is close (under the text from the largest sizes, so the title keeps the
    /// width), and the clock large ("11:00" with a small "AM", then " – 12:00 PM").
    struct UpNextCard: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let item: NextUpItem
        let formatter: TodayFormatter
        let onOpen: () -> Void

        var body: some View {
            let title = item.title ?? TodayStrings.text("today.invitation.untitled")
            let time = formatter.upcoming(item.time)
            let place = item.location ?? (item.isOnline ? TodayStrings.text("today.online") : nil)
            let range = formatter.range(item)
            let showsChip = item.isHappeningNow || item.isCountdown
            let chipBelow = dynamicTypeSize.isExtraLargeText
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                    TodayPinnedRow {
                        TodayTile(systemImage: item.location != nil ? "mappin.and.ellipse" : "clock", tone: .teal)
                    } content: {
                        HStack(spacing: Spacing.mediumSmall) {
                            VStack(alignment: .leading, spacing: 0) {
                                Text(title)
                                    .waiveraTextStyle(.titleMedium)
                                    .fontWeight(.bold)
                                    .foregroundStyle(Palette.text)
                                    .lineLimit(UpNextCard.titleLines)
                                if let place {
                                    Text(place)
                                        .waiveraTextStyle(.bodySmall)
                                        .foregroundStyle(Palette.textSecondary)
                                        .lineLimit(2)
                                }
                                if showsChip && chipBelow {
                                    CountdownChip(text: time).padding(.top, Spacing.extraSmall)
                                }
                            }
                            .multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            if showsChip && !chipBelow { CountdownChip(text: time) }
                        }
                    }
                    if let start = item.start {
                        clock(start)
                    } else if !showsChip {
                        Text(time)
                            .waiveraTextStyle(.clockTime)
                            .foregroundStyle(Palette.text)
                    }
                }
                .padding(Spacing.medium)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.press(.card))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text(
                    TodayStrings.spoken(
                        time,
                        title,
                        range.map { TodayStrings.joined($0, place) } ?? place,
                        item.isHappeningNow ? TodayStrings.text("today.nextUp.happeningNow") : nil
                    )
                )
            )
            .accessibilityHint(Text(TodayStrings.text("today.hint.openEvent")))
            .accessibilityAddTraits(.isButton)
            .todayCard(radius: Radius.upNextCard)
            .todayCardSpacing()
        }

        /// "11:00" large with a small "AM"; the end time's text starts with the space before its
        /// dash, so the dash has the same space either side.
        private func clock(_ start: ClockTime) -> some View {
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(formatter.clock(start))
                    .waiveraTextStyle(.displayTime)
                    .foregroundStyle(Palette.text)
                    .padding(.trailing, Spacing.extraSmall)
                Text(formatter.meridiem(start))
                    .waiveraTextStyle(.clockTime)
                    .foregroundStyle(Palette.textSecondary)
                if let end = item.end {
                    Text(
                        TodayStrings.format(
                            item.endsOnLaterDay ? "today.until.nextDay" : "today.until.dash",
                            formatter.time(end)
                        )
                    )
                    .waiveraTextStyle(.clockTime)
                    .foregroundStyle(Palette.textSecondary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(UpNextCard.clockMinimumScale)
        }

        private static let titleLines = 3
        /// The clock line never wraps; at the largest sizes it shrinks a little instead.
        private static let clockMinimumScale: CGFloat = 0.6
    }

    /// A birthday or work anniversary today, as a small moment rather than a list row (Android
    /// `CelebrationCard`): the plain avatar, what it is, the sentence with the name kept to two
    /// lines (wave 29 N3) and the one celebration emoji in its own tile, on the celebration wash.
    /// "Send wishes" opens a direct chat with them and is its own target, so VoiceOver reaches it
    /// separately; it is hidden on your own card. Confetti bursts over the card when it first
    /// shows (nothing under Reduce Motion). The card body opens the schedule.
    struct CelebrationCard: View {
        let item: CelebrationItem
        var burstSeed: UInt64 = 0
        var isOpeningWishes = false
        let onOpen: () -> Void
        var onSendWishes: (() -> Void)?

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            let sentence = TodayStrings.celebration(item)
            VStack(alignment: .leading, spacing: 0) {
                Button(action: onOpen) {
                    HStack(spacing: Spacing.mediumSmall) {
                        TodayAvatar(userId: item.userId, name: name, size: ControlSize.avatarMedium)
                        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                            Text(TodayStrings.celebrationLabel(item))
                                .waiveraTextStyle(.labelMedium)
                                .foregroundStyle(Palette.textSecondary)
                            WordSafeText(text: sentence, style: .titleSmall, lines: CelebrationCard.sentenceLines)
                                .foregroundStyle(Palette.text)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        // The same emoji tile as Schedule and Profile: one celebration treatment (UI9-07).
                        EmojiTile(TodayStrings.celebrationEmoji(item))
                    }
                    .padding(Spacing.medium)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.card))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(sentence))
                .accessibilityHint(Text(TodayStrings.text("today.hint.openSchedule")))
                .accessibilityAddTraits(.isButton)
                if let onSendWishes, !item.isMe {
                    wishes(onSendWishes)
                }
            }
            .background {
                ZStack {
                    Palette.surface
                    BrandWashFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: Radius.upNextCard, style: .continuous))
            }
            .overlay { CelebrationBurst(trigger: item.userId, seed: burstSeed) }
            .todayCardSpacing()
        }

        private var name: String { item.name ?? TodayStrings.text("today.celebration.nameFallback") }

        /// Under the sentence while it fits on one line; at the card's content start on a narrow
        /// card or at the accessibility sizes, so its two words never wrap (UI11-03).
        @ViewBuilder private func wishes(_ action: @escaping () -> Void) -> some View {
            if dynamicTypeSize.isExtraLargeText {
                wishesButton(action).padding(.leading, Spacing.medium)
            } else {
                ViewThatFits(in: .horizontal) {
                    wishesButton(action).padding(.leading, CelebrationCard.wishesIndent)
                    wishesButton(action).padding(.leading, Spacing.medium)
                }
            }
        }

        private func wishesButton(_ action: @escaping () -> Void) -> some View {
            WaiveraButton(
                TodayStrings.text("today.sendWishes"),
                variant: .tonalOnWash,
                systemImage: "bubble.left",
                isLoading: isOpeningWishes,
                loadingTitle: TodayStrings.text("today.sendWishes.opening"),
                fillsWidth: false,
                action: action
            )
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(Text(TodayStrings.format("today.sendWishes.a11y", name)))
            .padding(.trailing, Spacing.medium)
            .padding(.bottom, Spacing.medium)
            .frame(maxWidth: .infinity, alignment: .leading)
        }

        private static let sentenceLines = 2
        /// Lines the button up with the sentence: the card padding, the avatar and the gap.
        private static let wishesIndent = Spacing.medium + ControlSize.avatarMedium + Spacing.mediumSmall
    }

    extension NextUpItem {
        /// All-day items have no clock range.
        var isAllDay: Bool { start == nil }
    }

    #if DEBUG
        #Preview("Light") {
            let items = TodayPreviewStates.populated().nextUp.items
            ScrollView {
                VStack(spacing: 0) {
                    UpNextCard(item: items[0], formatter: TodayFormatting.shared) {}
                    ForEach(items.dropFirst()) { NextUpRow(item: $0, formatter: TodayFormatting.shared) {} }
                    ForEach(TodayPreviewStates.populated().celebrations) {
                        CelebrationCard(item: $0, onOpen: {}, onSendWishes: {})
                    }
                }
            }
            .background(Palette.background)
        }

        #Preview("Dark, AX5") {
            let items = TodayPreviewStates.longContent().nextUp.items
            ScrollView {
                VStack(spacing: 0) {
                    if let first = items.first { UpNextCard(item: first, formatter: TodayFormatting.shared) {} }
                    ForEach(TodayPreviewStates.longContent().celebrations) {
                        CelebrationCard(item: $0, isOpeningWishes: true, onOpen: {}, onSendWishes: {})
                    }
                }
            }
            .background(Palette.background)
            .preferredColorScheme(.dark)
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
