#if canImport(UIKit)
    import SwiftUI
    import WaiveraData
    import WaiveraDesign

    /// Who is signed in, for the hero bar's account button. Nil hides the button.
    public struct ScheduleAccount {
        public var name: String
        public var image: Image?
        public var open: () -> Void

        public init(name: String, image: Image? = nil, open: @escaping () -> Void) {
            self.name = name
            self.image = image
            self.open = open
        }
    }

    /// The schedule screen drawn from plain state, so previews and snapshots render every state
    /// without a data layer: the hero bar, the Day / Week / Month control, one status banner, the
    /// calendar card (period row over the grid, which slides with its title on a step), the
    /// day heading and the agenda.
    public struct ScheduleScreenView: View {
        let state: ScheduleUIState
        let actions: ScheduleActions
        let account: ScheduleAccount?
        let canSendWishes: Bool
        let refresh: @Sendable () async -> Void

        public init(
            state: ScheduleUIState,
            actions: ScheduleActions = ScheduleActions(),
            account: ScheduleAccount? = nil,
            canSendWishes: Bool = true,
            refresh: @escaping @Sendable () async -> Void = {}
        ) {
            self.state = state
            self.actions = actions
            self.account = account
            self.canSendWishes = canSendWishes
            self.refresh = refresh
        }

        public var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    HeroSection {
                        ScheduleHeroBar(
                            showsJumpToToday: state.showsJumpToToday,
                            account: account,
                            onToday: { actions.goToToday() }
                        )
                    } content: {
                        EmptyView()
                    }
                    VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                        SegmentedControl(options: viewOptions, selection: viewSelection)
                            .accessibilityLabel(Text(ScheduleStrings.text("schedule.view.label")))
                            .padding(.bottom, Spacing.extraSmall)
                        ScheduleBanners(state: state, actions: actions)
                        calendarCard
                        if state.view != .day, state.agenda.isFailure == false {
                            AgendaHeader(state: state)
                                .padding(.top, Spacing.medium)
                                .padding(.bottom, Spacing.small)
                        }
                        AgendaSection(state: state, canSendWishes: canSendWishes, actions: actions)
                            .padding(.top, state.view == .day ? Spacing.small : 0)
                    }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.bottom, Spacing.large)
                }
            }
            .background(Palette.background)
            .refreshable { [refresh] in await refresh() }
            .accessibilityAction(named: Text(ScheduleStrings.text("schedule.refresh"))) {
                Task { await refresh() }
            }
        }

        /// The period row and the grid read as one card. The grid moves with its title: a step
        /// slides both a third of the way in the same direction while the old period fades on the
        /// quick exit, and a view change only fades. The card clips, so neither period draws
        /// past it (M2-04). Picking a day keeps the period, so the grid updates in place.
        private var calendarCard: some View {
            let shape = RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous)
            return VStack(spacing: 0) {
                PeriodRow(state: state, onStep: { actions.step($0) })
                if state.view != .day, !state.cells.isEmpty {
                    SwapView(
                        state.period,
                        axis: state.periodStep == 0 ? nil : .horizontal,
                        forward: state.periodStep >= 0
                    ) { _ in
                        ScheduleGrid(
                            view: state.view,
                            cells: state.cells,
                            weekdayHeaders: state.weekdayHeaders,
                            onSelect: { actions.selectDate($0) }
                        )
                        .padding(.bottom, Spacing.small)
                    }
                    .clipped()
                }
            }
            .background(Palette.surface, in: shape)
            .clipShape(shape)
        }

        private var viewOptions: [SegmentedChips<CalendarPeriod>.Option] {
            [
                .init(.day, title: ScheduleStrings.text("schedule.view.day")),
                .init(.week, title: ScheduleStrings.text("schedule.view.week")),
                .init(.month, title: ScheduleStrings.text("schedule.view.month")),
            ]
        }

        private var viewSelection: Binding<CalendarPeriod> {
            // Captures only Sendable values: Binding's closures are @Sendable.
            let current = state.view
            let select = actions.selectView
            return Binding(get: { current }, set: { select($0) })
        }
    }

    /// One status signal under the view control, above the grid, so a failure is seen without
    /// scrolling: a failed first load wins over offline and a failed refresh. Milestones and a
    /// fallback zone get their own quiet banners.
    private struct ScheduleBanners: View {
        let state: ScheduleUIState
        let actions: ScheduleActions

        var body: some View {
            VStack(spacing: Spacing.small) {
                if case .error(let error) = state.agenda {
                    BannerView(
                        .error,
                        title: ScheduleStrings.text("schedule.error.title"),
                        message: error.userMessage,
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { actions.retry() }
                    )
                } else if let notice = state.feedNotice {
                    BannerView(
                        .reconnecting,
                        title: ScheduleStrings.text("schedule.feedFailed.title"),
                        message: notice,
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { actions.retry() }
                    )
                }
                if state.milestonesFailed, !state.agenda.isFailure {
                    BannerView(
                        .reconnecting,
                        message: ScheduleStrings.text("schedule.milestonesFailed"),
                        actionTitle: ScheduleStrings.text("schedule.retry"),
                        action: { actions.retryMilestones() }
                    )
                }
                if state.isFallbackZone, let notice = state.zoneNotice {
                    BannerView(.info, message: notice)
                }
            }
            .padding(.bottom, Spacing.small)
        }
    }

    /// The compact hero bar: the mark, "Schedule", "Jump to today" when today is out of sight
    /// (pull to refresh refreshes, so there is no refresh button), and the account avatar.
    private struct ScheduleHeroBar: View {
        let showsJumpToToday: Bool
        let account: ScheduleAccount?
        let onToday: () -> Void

        @Environment(\.waiveraAccountMenu) private var shellAccount

        var body: some View {
            HStack(spacing: 0) {
                // The avatar is drawn below, after "Jump to today", so the bar's own fallback
                // to the shell's account is turned off here; one avatar, never two.
                HeroTopBar(title: ScheduleStrings.title)
                    .environment(\.waiveraAccountMenu, nil)
                PopVisibility(isVisible: showsJumpToToday) {
                    Button(action: onToday) {
                        Image(systemName: "calendar.badge.clock")
                            .font(WaiveraFont.bodyEmphasis)
                            .foregroundStyle(HeroPalette.onHeader)
                            .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(ScheduleStrings.text("schedule.jumpToToday")))
                    .accessibilityHint(Text(ScheduleStrings.text("schedule.today.hint")))
                }
                if let account = resolvedAccount {
                    Button(action: account.open) {
                        AvatarView(
                            name: account.name,
                            image: account.image ?? shellAccount?.image,
                            size: CGFloat(HeroMetrics.barAvatar),
                            fill: .hero
                        )
                        .frame(width: ControlSize.iconButton, height: ControlSize.iconButton)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.press(.compact))
                    .accessibilityLabel(Text(ScheduleStrings.text("schedule.accountMenu")))
                    .padding(.trailing, Spacing.small)
                }
            }
        }

        /// The screen's own account, else the one the app shell provides.
        private var resolvedAccount: ScheduleAccount? {
            account ?? shellAccount.map { ScheduleAccount(name: $0.name, image: $0.image, open: $0.openMenu) }
        }
    }

    extension AgendaState {
        var isFailure: Bool {
            if case .error = self { return true }
            return false
        }
    }
#endif
