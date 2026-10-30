#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// What the Today screen can ask for. Navigation goes through `open`, which the screen maps
    /// to the router closures.
    struct TodayActions {
        var reload: () -> Void = {}
        var open: (TodayDestination, Int64?) -> Void = { _, _ in }
        /// The hero bar's avatar; nil hides the button's action until the app wires the account menu.
        var openAccount: (() -> Void)?
        var respond: (String, Bool) -> Void = { _, _ in }
        /// "Send wishes" on a celebration card, with the person's user id; nil hides the button.
        var sendWishes: ((String) -> Void)?
        var toggleNeedsYou: () -> Void = {}
        var setFilter: (ActivityFilter) -> Void = { _ in }
        var toggleUnreadOnly: () -> Void = {}
        var clearFilters: () -> Void = {}
        var markRead: (Int64) -> Void = { _ in }
        var markAllRead: () -> Void = {}
        var loadMore: () -> Void = {}
        var retryMore: () -> Void = {}
    }

    /// Formatters are costly to build, so every Today view shares one.
    @MainActor
    enum TodayFormatting {
        static let shared = TodayFormatter()
    }

    /// The stateless Today screen: the plum hero, then the sheet in priority order. A working day
    /// goes Needs you, Your day, Up next, Celebrations, Activity; all caught up leads with Up next
    /// and Celebrations under the reward. Loads under ~300 ms show nothing rather than flashing a
    /// skeleton; slower ones cross-fade from the skeleton.
    struct TodayContent: View {
        let state: TodayState
        let actions: TodayActions
        let onRefresh: @Sendable () async -> Void
        @State private var windowHeight: CGFloat = 0

        private var formatter: TodayFormatter { TodayFormatting.shared }
        private var compact: Bool { HeroMetrics.isShortWindow(height: Double(windowHeight)) }

        var body: some View {
            ScrollView {
                VStack(spacing: 0) {
                    TodayHero(state: state, actions: actions, compact: compact)
                    sheet
                }
                .padding(.bottom, Spacing.extraLarge)
            }
            .environment(\.todayCompactWindow, compact)
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.height + proxy.safeAreaInsets.top + proxy.safeAreaInsets.bottom
            } action: { height in
                windowHeight = height
            }
            .background(Palette.background)
            .refreshable { [onRefresh] in await onRefresh() }
            .waiveraAnimation(.layout, value: state)
            .accessibilityIdentifier("today.list")
        }

        @ViewBuilder private var sheet: some View {
            if let error = state.loadError {
                EmptyStateView.error(
                    title: TodayStrings.text("today.error.title"),
                    message: error.userMessage,
                    onRetry: actions.reload
                )
            } else {
                LoadingContent(isLoading: state.isInitialLoad) {
                    LazyVStack(spacing: 0) {
                        quietLine
                        needsYouSection
                        if state.isAllCaughtUp {
                            nextUpSection
                            celebrationSection
                            yourDay
                        } else {
                            yourDay
                            nextUpSection
                            celebrationSection
                        }
                        activitySection
                    }
                } skeleton: {
                    TodaySkeleton()
                }
            }
        }

        // MARK: Quiet line

        @ViewBuilder private var quietLine: some View {
            if let quiet = state.quietStatus {
                QuietLine(text: formatter.quiet(quiet), systemImage: Self.icon(quiet))
                    .accessibilityIdentifier("today.quietLine")
            }
        }

        private static func icon(_ status: QuietStatus) -> String {
            switch status {
            case .offline: "wifi.slash"
            case .stale: "clock.arrow.circlepath"
            }
        }

        // MARK: Needs you

        /// All caught up is the hero's reward, so the sheet goes straight on to the day.
        @ViewBuilder private var needsYouSection: some View {
            let section = state.needsYou
            if !state.isAllCaughtUp && (section.failed || !section.items.isEmpty) {
                TodaySectionHeader(
                    title: TodayStrings.text("today.section.needsYou"),
                    first: true,
                    count: section.failed ? nil : section.totalCount
                ) {
                    needsYouToggle(section)
                }
                if section.failed {
                    SectionErrorView(message: TodayStrings.text("today.needsYou.failed"), onRetry: actions.reload)
                } else {
                    ForEach(section.items) { item in
                        NeedsYouRow(item: item, formatter: formatter, onOpen: actions.open, onRespond: actions.respond)
                            .transition(.opacity)
                    }
                }
            }
        }

        /// "Show all" (VoiceOver: "Show 2 more") while items are folded away, "Show less" once open.
        @ViewBuilder private func needsYouToggle(_ section: NeedsYouSection) -> some View {
            if section.isExpanded {
                TodayTextButton(title: TodayStrings.text("today.needsYou.showLess"), action: actions.toggleNeedsYou)
                    .accessibilityIdentifier("today.needsYou.toggle")
            } else if section.hiddenCount > 0 {
                TodayTextButton(title: TodayStrings.text("today.needsYou.showAll"), action: actions.toggleNeedsYou)
                    .accessibilityLabel(Text(TodayStrings.showMore(section.hiddenCount)))
                    .accessibilityIdentifier("today.needsYou.toggle")
            }
        }

        // MARK: Your day

        @ViewBuilder private var yourDay: some View {
            if let day = state.day {
                let next = state.nextUp.items.first { $0.startsToday && $0.start != nil }
                YourDayCard(day: day, next: next) { actions.open(.event(id: $0), nil) }
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.top, Spacing.mediumPlus)
                    .padding(.bottom, Spacing.extraSmall)
            }
        }

        // MARK: Up next

        @ViewBuilder private var nextUpSection: some View {
            let section = state.nextUp
            TodaySectionHeader(title: TodayStrings.text("today.section.nextUp"), first: state.isAllCaughtUp) {
                TodayTextButton(
                    title: TodayStrings.text("today.seeSchedule"),
                    hint: TodayStrings.text("today.seeSchedule.hint"),
                    action: { actions.open(.schedule, nil) }
                )
                .accessibilityIdentifier("today.seeSchedule")
            }
            if section.failed {
                SectionErrorView(message: TodayStrings.text("today.nextUp.failed"), onRetry: actions.reload)
            } else if !section.isReady {
                SectionSkeleton()
            } else if section.items.isEmpty {
                QuietLine(text: TodayStrings.text("today.nextUp.empty"))
            } else {
                if let first = section.featured {
                    UpNextCard(item: first, formatter: formatter) { actions.open(.event(id: first.eventId), nil) }
                }
                ForEach(section.others) { item in
                    NextUpRow(item: item, formatter: formatter) { actions.open(.event(id: item.eventId), nil) }
                }
            }
            if state.usesFallbackTimeZone {
                QuietLine(
                    text: TodayStrings.format("today.nextUp.fallbackZone", state.timeZone.identifier),
                    systemImage: "globe"
                )
            }
        }

        // MARK: Celebrations

        @ViewBuilder private var celebrationSection: some View {
            if !state.celebrations.isEmpty || state.celebrationsFailed {
                TodaySectionHeader(title: TodayStrings.text("today.section.celebrations"))
                if state.celebrationsFailed {
                    SectionErrorView(message: TodayStrings.text("today.celebration.failed"), onRetry: actions.reload)
                }
                ForEach(Array(state.celebrations.enumerated()), id: \.element.id) { index, item in
                    CelebrationCard(
                        item: item,
                        burstSeed: UInt64(index),
                        isOpeningWishes: state.openingWishesFor == item.userId,
                        onOpen: { actions.open(.schedule, nil) },
                        onSendWishes: wishesAction(for: item)
                    )
                }
            }
        }

        private func wishesAction(for item: CelebrationItem) -> (() -> Void)? {
            guard let send = actions.sendWishes else { return nil }
            return { send(item.userId) }
        }

        // MARK: Activity

        @ViewBuilder private var activitySection: some View {
            let section = state.activity
            ActivityHeader(
                section: section,
                onSeeAll: { actions.open(.activity, nil) },
                onMarkAllRead: actions.markAllRead
            )
            if section.failed {
                SectionErrorView(message: TodayStrings.text("today.activity.failed"), onRetry: actions.reload)
            } else if !section.isReady {
                SectionSkeleton()
            } else if section.isEmpty {
                EmptyStateView(
                    illustration: .activity,
                    title: TodayStrings.text("today.activity.empty.title"),
                    message: TodayStrings.text("today.activity.empty.message")
                )
            } else {
                ActivityFilterBar(
                    filter: section.filter,
                    unreadOnly: section.unreadOnly,
                    onFilter: actions.setFilter,
                    onToggleUnread: actions.toggleUnreadOnly
                )
                if section.isFilteredEmpty {
                    EmptyStateView(
                        illustration: .search,
                        title: TodayStrings.text("today.activity.filtered.title"),
                        message: TodayStrings.text("today.activity.filtered.message"),
                        actionTitle: TodayStrings.text("today.activity.clearFilters"),
                        action: actions.clearFilters
                    )
                }
                ForEach(section.rows) { row in
                    ActivityItemRow(
                        row: row,
                        formatter: formatter,
                        onOpen: { actions.open(.chat(row.destination), row.id) },
                        onMarkRead: { actions.markRead(row.id) }
                    )
                }
                ActivityFooter(section: section, onLoadMore: actions.loadMore, onRetry: actions.retryMore)
            }
        }
    }

    extension View {
        /// Full-bleed list rows: the row draws its own padding and background.
        func todayListRow() -> some View {
            listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
        }
    }
#endif
