#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The top of Today: the plum hero with the bar, the date and greeting, the glass summary card
    /// (count-only ring, what needs you, what's next) and three stat tiles. When everything is
    /// handled it becomes the reward: the big ring, "You're all caught up 🎉" and confetti once a day.
    struct TodayHero: View {
        let state: TodayState
        let actions: TodayActions
        /// A short window (under 700pt) compacts the hero so two Needs you cards still show.
        let compact: Bool

        var body: some View {
            HeroSection(trail: state.isAllCaughtUp ? .reward : .tab, compact: compact) {
                HeroTopBar(
                    title: TodayStrings.text("today.title"),
                    accountName: state.accountName.isEmpty ? nil : state.accountName,
                    accountLabel: TodayStrings.text("today.account"),
                    onAccount: actions.openAccount
                )
            } content: {
                if state.isAllCaughtUp {
                    RewardHeroBody(state: state)
                } else {
                    DayHeroBody(state: state, compact: compact, onOpenEvent: { actions.open(.event(id: $0), nil) })
                }
            }
        }
    }

    /// The working day: date, greeting, summary card and stats.
    private struct DayHeroBody: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let state: TodayState
        let compact: Bool
        let onOpenEvent: (String) -> Void
        /// The summary keeps the day it showed while it goes back to loading and fades out.
        @State private var shownProgress: TodayProgress?

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: Spacing.extraSmall + Spacing.xxSmall) {
                    if let date = state.date {
                        Text(TodayFormatting.shared.longDay(date).uppercased())
                            .waiveraTextStyle(.heroEyebrow)
                            .foregroundStyle(HeroPalette.onHeaderSecondary)
                            .padding(.top, Spacing.extraSmall)
                            .accessibilityLabel(Text(TodayFormatting.shared.longDay(date)))
                    }
                    if let greeting = state.greeting {
                        WordSafeText(
                            text: TodayStrings.greeting(greeting),
                            style: compact ? .heroGreetingCompact : .heroGreeting,
                            lines: NameLines.greeting
                        )
                        .foregroundStyle(HeroPalette.onHeader)
                        .accessibilityAddTraits(.isHeader)
                    }
                }
                .padding(.horizontal, Spacing.gutter + Spacing.extraSmall)
                .padding(.bottom, compact ? Spacing.small : Spacing.medium + Spacing.xxSmall)
                summary
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.bottom, compact ? Spacing.small : Spacing.small + Spacing.xxSmall)
                TodayStatGroup(
                    stats: [
                        TodayStat(TodayStrings.stat(state.stats.eventsToday, label: "today.stat.eventsToday")),
                        TodayStat(TodayStrings.stat(state.stats.unreadChats, label: "today.stat.unreadChats")),
                        TodayStat(TodayStrings.stat(state.stats.eventsThisWeek, label: "today.stat.eventsWeek")),
                    ],
                    compact: compact && !dynamicTypeSize.isLargeText
                )
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.mediumSmall)
            }
            .onAppear { shownProgress = state.progress ?? shownProgress }
            .onChange(of: state.progress) { shownProgress = state.progress ?? shownProgress }
        }

        /// The glass card is one surface around the load swap and only what is inside it swaps,
        /// so the card itself never blinks between the placeholder and the summary (M4-02). A
        /// failed first load shows no card.
        @ViewBuilder private var summary: some View {
            let shown = state.progress ?? shownProgress
            if shown != nil || state.loadError == nil {
                HeroCard(compact: compact) {
                    LoadingContent(isLoading: shown == nil) {
                        if let shown {
                            SummaryCard(
                                progress: shown,
                                kinds: state.needsYou.kinds,
                                next: state.nextUp.featured,
                                compact: compact,
                                onOpenEvent: onOpenEvent
                            )
                        }
                    } skeleton: {
                        SummaryPlaceholder(compact: compact)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(TodayStrings.text("today.loadingSummary")))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    /// The ring with what needs the person beside it, and the next item under a hairline. At
    /// large text the ring sits above the words so the headline keeps the card's full width.
    private struct SummaryCard: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let progress: TodayProgress
        let kinds: [NeedsYouKind: Int]
        let next: NextUpItem?
        let compact: Bool
        let onOpenEvent: (String) -> Void

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? Spacing.small : Spacing.mediumSmall) {
                if dynamicTypeSize.isLargeText {
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                        ring
                        words
                    }
                } else {
                    HStack(spacing: Spacing.medium + Spacing.xxSmall) {
                        ring
                        words.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                if let next {
                    HeroNextRow(item: next, compact: compact) { onOpenEvent(next.eventId) }
                }
            }
        }

        /// The count inside the ring grows to 130%, which the compact ring has no room for.
        private var ring: some View {
            ProgressRing(
                done: progress.handled,
                total: progress.total,
                accessibilityText: TodayStrings.ring(progress),
                compact: compact && !dynamicTypeSize.isLargeText
            )
        }

        /// "4 things need you" and, under it, what is waiting by kind. The ring already shows how
        /// many are handled, so the line says something new (owner's pick, option A).
        private var words: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                Text(TodayStrings.needsYouHeadline(open: progress.open))
                    .waiveraTextStyle(.heroTitle)
                    .foregroundStyle(HeroPalette.onHeader)
                    .fixedSize(horizontal: false, vertical: true)
                if let subline = TodayStrings.subline(kinds) {
                    Text(subline)
                        .waiveraTextStyle(.heroBody)
                        .foregroundStyle(HeroPalette.onHeaderSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    /// "NEXT · 11:00 AM / Client home visit" with a countdown chip while it is close. From 150%
    /// the chip moves under the title so the kicker and title keep the width (UI11-01).
    private struct HeroNextRow: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let item: NextUpItem
        let compact: Bool
        let onOpen: () -> Void

        var body: some View {
            let formatter = TodayFormatting.shared
            let title = item.title ?? TodayStrings.text("today.invitation.untitled")
            let upcoming = formatter.upcoming(item.time)
            let countdown = item.isCountdown
            let kicker: String =
                if item.isHappeningNow {
                    upcoming
                } else if countdown, let start = item.start {
                    TodayStrings.format("today.next", formatter.time(start))
                } else {
                    TodayStrings.format("today.next", upcoming)
                }
            let stacked = dynamicTypeSize.isExtraLargeText
            VStack(spacing: 0) {
                Rectangle()
                    .fill(HeroPalette.cardBorder)
                    .frame(height: Spacing.hairline)
                Button(action: onOpen) {
                    HStack(alignment: stacked ? .top : .center, spacing: Spacing.small) {
                        Image(systemName: "clock")
                            .resizable()
                            .scaledToFit()
                            .frame(width: ControlSize.iconTileSmallGlyph, height: ControlSize.iconTileSmallGlyph)
                            .foregroundStyle(HeroPalette.nextIcon)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(kicker.uppercased())
                                .waiveraTextStyle(.heroEyebrow)
                                .foregroundStyle(HeroPalette.onHeaderSecondary)
                            Text(title)
                                .waiveraTextStyle(.titleSmall)
                                .fontWeight(.bold)
                                .foregroundStyle(HeroPalette.onHeader)
                                .lineLimit(2)
                            if stacked, countdown {
                                CountdownChip(text: upcoming, onHero: true).padding(.top, Spacing.extraSmall)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        if !stacked, countdown {
                            CountdownChip(text: upcoming, onHero: true)
                        }
                    }
                    .padding(.top, compact ? Spacing.small : Spacing.mediumSmall)
                    .frame(minHeight: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.press(.row))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(TodayStrings.format("today.next.label", title, upcoming)))
                .accessibilityHint(Text(TodayStrings.text("today.hint.openEvent")))
                .accessibilityAddTraits(.isButton)
            }
        }
    }

    /// The card's shape while Needs you loads: the ring's track, the headline and subline bars,
    /// and the Next row under its hairline, so it is as tall as the summary that replaces it.
    private struct SummaryPlaceholder: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let compact: Bool

        var body: some View {
            VStack(alignment: .leading, spacing: compact ? Spacing.small : Spacing.mediumSmall) {
                HStack(spacing: Spacing.medium + Spacing.xxSmall) {
                    let ring = compact && !dynamicTypeSize.isLargeText ? ControlSize.ringCompact : ControlSize.ring
                    Circle()
                        .fill(HeroPalette.tile)
                        .frame(width: ring, height: ring)
                    VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                        GlassBar(style: .heroTitle, share: 0.8)
                        GlassBar(style: .heroBody, share: 0.55)
                    }
                }
                Rectangle()
                    .fill(HeroPalette.cardBorder)
                    .frame(height: Spacing.hairline)
                HStack(spacing: Spacing.small) {
                    Circle()
                        .fill(HeroPalette.tile)
                        .frame(width: ControlSize.iconTileSmallGlyph, height: ControlSize.iconTileSmallGlyph)
                    VStack(alignment: .leading, spacing: 0) {
                        GlassBar(style: .heroEyebrow, share: 0.35)
                        GlassBar(style: .titleSmall, share: 0.6)
                    }
                }
            }
        }
    }

    /// One line of `style`'s height with a glass bar through it, `share` of the width long.
    private struct GlassBar: View {
        let style: TextStyleToken
        let share: Double

        var body: some View {
            Text(verbatim: " ")
                .waiveraTextStyle(style)
                .frame(maxWidth: .infinity, alignment: .leading)
                .hidden()
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        RoundedRectangle(cornerRadius: Radius.countBadge, style: .continuous)
                            .fill(HeroPalette.tile)
                            .frame(width: proxy.size.width * share, height: ControlSize.skeletonLine)
                            .frame(maxHeight: .infinity, alignment: .center)
                    }
                }
                .accessibilityHidden(true)
        }
    }

    /// All caught up: the reward ring, the one 🎉 headline, the handled count and the day's stats.
    /// Confetti plays once per day in the employee's zone, remembered across launches.
    private struct RewardHeroBody: View {
        let state: TodayState
        @AppStorage(RewardBurst.storageKey) private var lastBurstDay = ""
        @State private var burstTrigger: String?

        var body: some View {
            VStack(spacing: 0) {
                VStack(spacing: 0) {
                    RewardRing(accessibilityText: nil)
                        .padding(.top, ControlSize.rewardHalo / 2)
                    Text(TodayStrings.text("today.caughtUp.title"))
                        .waiveraTextStyle(.heroReward)
                        .foregroundStyle(HeroPalette.onHeader)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, Spacing.large)
                        .accessibilityAddTraits(.isHeader)
                    WordSafeText(
                        text: TodayStrings.caughtUp(
                            handled: state.progress?.handled ?? 0,
                            firstName: state.greeting?.firstName
                        ),
                        style: .heroBody,
                        lines: NameLines.greeting,
                        alignment: .center
                    )
                    .foregroundStyle(HeroPalette.onHeaderSecondary)
                    .padding(.top, Spacing.extraSmall + Spacing.xxSmall)
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, Spacing.gutter)
                .padding(.vertical, Spacing.extraSmall)
                .overlay { CelebrationBurst(trigger: burstTrigger, seed: RewardBurst.seed(state.date)) }
                TodayStatGroup(stats: [
                    TodayStat(TodayStrings.handledStat(state.progress)),
                    TodayStat(TodayStrings.stat(state.stats.eventsToday, label: "today.stat.eventsToday")),
                    TodayStat(TodayStrings.stat(state.stats.eventsThisWeek, label: "today.stat.eventsWeek")),
                ])
                .padding(.horizontal, Spacing.gutter)
                .padding(.top, Spacing.mediumPlus + Spacing.xxSmall)
                .padding(.bottom, Spacing.mediumSmall)
            }
            .onAppear(perform: claimBurst)
        }

        /// The burst plays the first time the reward shows on a day; a relaunch, a scroll back or
        /// the next visit to the tab the same day stays still.
        private func claimBurst() {
            guard let day = state.date?.isoString, burstTrigger == nil else { return }
            guard RewardBurst.plays(today: day, lastPlayed: lastBurstDay) else { return }
            lastBurstDay = day
            burstTrigger = day
        }
    }

    /// A countdown chip ("in 30 min"): mint on deep teal glass on the hero, teal on the sheet.
    struct CountdownChip: View {
        let text: String
        var onHero = false

        var body: some View {
            Text(text)
                .waiveraTextStyle(.chip)
                .foregroundStyle(onHero ? HeroPalette.onChip : TileTone.teal.contentColor)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, Spacing.small)
                .padding(.vertical, onHero ? Spacing.xxSmall : Spacing.extraSmall)
                .background(
                    onHero ? HeroPalette.chip : TileTone.teal.containerColor,
                    in: RoundedRectangle(cornerRadius: Radius.countBadge, style: .continuous)
                )
        }
    }

    extension NextUpItem {
        /// Close enough for a countdown chip ("in 30 min", "in 2 hr").
        var isCountdown: Bool {
            switch time {
            case .inMinutes, .inHours: true
            default: false
            }
        }
    }

    #if DEBUG
        #Preview("Light") {
            ScrollView {
                TodayHero(state: TodayPreviewStates.populated(), actions: TodayActions(), compact: false)
            }
            .background(Palette.background)
        }

        #Preview("Dark, reward") {
            ScrollView {
                TodayHero(state: TodayPreviewStates.caughtUp(), actions: TodayActions(), compact: false)
            }
            .background(Palette.background)
            .preferredColorScheme(.dark)
        }

        #Preview("AX5, long names") {
            ScrollView {
                TodayHero(state: TodayPreviewStates.longContent(), actions: TodayActions(), compact: false)
            }
            .background(Palette.background)
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
