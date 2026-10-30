#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The message list, anchored to the bottom (11 pitfalls: no manual offsets). Pages older
    /// rows when the top is reached, keeps the newest row in view while the reader is at the
    /// bottom, offers "Jump to latest" when they are not, and runs the screen's scroll commands.
    /// Inserts and removes move the other rows on the layout spring (spec §4.4). While my own
    /// send lands, placement holds for `MotionTiming.listSettle`, so the rows above follow the
    /// bubble's own arrival instead of chasing it (Android `rememberListMotion`).
    struct TimelineList<Header: View>: View {
        let items: [TimelineItem]
        let context: RowContext
        let actions: MessageRowActions
        let hasOlder: Bool
        let isLoadingOlder: Bool
        let scrollCommand: ScrollCommand?
        let accessibilityLabelKey: String
        var onLoadOlder: () -> Void = {}
        @ViewBuilder var header: () -> Header

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var bottomVisibleId: String?
        @State private var handledCommand: Int?
        /// The newest row when the list first showed: a send from before does not land again.
        @State private var initialNewestId: String?
        @State private var settledLandingId: String?

        private static var bottomId: String { "timeline-bottom" }
        private var isAtLatest: Bool {
            bottomVisibleId == nil || bottomVisibleId == Self.bottomId || bottomVisibleId == items.last?.id
        }

        /// My own send that is landing now, if any.
        private var landingId: String? {
            guard let newest = items.last, newest.isOwnLiveSend, newest.id != initialNewestId else { return nil }
            return newest.id == settledLandingId ? nil : newest.id
        }

        private var placementAnimation: Animation? {
            landingId == nil ? Motion.animation(.layout, reduceMotion: reduceMotion) : nil
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        header()
                        if hasOlder || isLoadingOlder {
                            OlderMessagesSkeleton()
                                .onAppear(perform: onLoadOlder)
                        }
                        ForEach(items) { item in
                            TimelineItemView(item: item, context: context, actions: actions)
                        }
                        Color.clear.frame(height: Spacing.small).id(Self.bottomId)
                    }
                    .scrollTargetLayout()
                    .animation(placementAnimation, value: items.map(\.id))
                }
                .scrollPosition(id: $bottomVisibleId, anchor: .bottom)
                .defaultScrollAnchor(.bottom)
                .scrollDismissesKeyboard(.interactively)
                .accessibilityLabel(ConversationStrings.text(accessibilityLabelKey))
                .overlay(alignment: .bottom) {
                    if !isAtLatest {
                        jumpButton { scrollToLatest(proxy) }
                            .padding(.bottom, Spacing.smallPlus)
                            .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                    }
                }
                .waiveraAnimation(.state, value: isAtLatest)
                .onChange(of: items.last?.id) { _, _ in
                    if isAtLatest { scrollToLatest(proxy, animated: false) }
                }
                .onChange(of: scrollCommand) { _, command in run(command, proxy) }
                .onAppear {
                    initialNewestId = items.last?.id
                    run(scrollCommand, proxy)
                }
                .task(id: landingId) {
                    guard let landing = landingId else { return }
                    try? await Task.sleep(for: .seconds(MotionTiming.listSettle))
                    guard !Task.isCancelled else { return }
                    settledLandingId = landing
                }
            }
        }

        /// Floats over the timeline, so it is lifted off the bubbles with a shadow and a strong
        /// hairline, with accent ink on the surface (Android `JumpToLatestPill`).
        private func jumpButton(_ action: @escaping () -> Void) -> some View {
            let shadow = Elevation.shadow(for: Elevation.level3)
            return Button(action: action) {
                HStack(spacing: Spacing.extraSmall) {
                    Image(systemName: "chevron.down")
                        .resizable()
                        .scaledToFit()
                        .fontWeight(.semibold)
                        .frame(width: ControlSize.iconSmall, height: ControlSize.iconSmall)
                        .accessibilityHidden(true)
                    Text(ConversationStrings.text("jump.to.latest"))
                        .waiveraTextStyle(.labelLarge)
                }
                .foregroundStyle(Palette.accent)
                .padding(.horizontal, Spacing.mediumSmall)
                .padding(.vertical, Spacing.small)
                .background(Palette.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(Palette.borderStrong, lineWidth: Spacing.hairline))
                .shadow(color: Palette.buttonRaise, radius: shadow.radius, x: 0, y: shadow.y)
                .frame(minHeight: ControlSize.minHitTarget)
                .contentShape(Capsule())
            }
            .buttonStyle(.pressScale)
            .accessibilityIdentifier("timeline.jumpToLatest")
        }

        private func run(_ command: ScrollCommand?, _ proxy: ScrollViewProxy) {
            guard let command, command.id != handledCommand else { return }
            handledCommand = command.id
            switch command.target {
            case .latest: scrollToLatest(proxy)
            case .key(let key):
                withAnimation(Motion.animation(.layout, reduceMotion: reduceMotion)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
        }

        private func scrollToLatest(_ proxy: ScrollViewProxy, animated: Bool = true) {
            let animation = animated ? Motion.animation(.layout, reduceMotion: reduceMotion) : nil
            withAnimation(animation) { proxy.scrollTo(Self.bottomId, anchor: .bottom) }
        }
    }

    extension TimelineList where Header == EmptyView {
        // swiftlint:disable:next function_parameter_count
        init(
            items: [TimelineItem],
            context: RowContext,
            actions: MessageRowActions,
            hasOlder: Bool,
            isLoadingOlder: Bool,
            scrollCommand: ScrollCommand?,
            accessibilityLabelKey: String,
            onLoadOlder: @escaping () -> Void = {}
        ) {
            self.init(
                items: items,
                context: context,
                actions: actions,
                hasOlder: hasOlder,
                isLoadingOlder: isLoadingOlder,
                scrollCommand: scrollCommand,
                accessibilityLabelKey: accessibilityLabelKey,
                onLoadOlder: onLoadOlder,
                header: { EmptyView() }
            )
        }
    }

    /// Two bubble placeholders at the top of the list while an older page loads (Android
    /// `OlderMessagesRow`); spoken as one "Loading older messages".
    private struct OlderMessagesSkeleton: View {
        var body: some View {
            VStack(spacing: Spacing.smallPlus) {
                ForEach(Array(ChatMetrics.skeletonWidthFractions.prefix(2).enumerated()), id: \.offset) { index, fraction in
                    HStack {
                        if !index.isMultiple(of: 2) { Spacer(minLength: 0) }
                        SkeletonBlock(
                            height: ChatMetrics.skeletonBubbleHeight,
                            cornerRadius: ChatMetrics.bubbleRadius
                        )
                        .containerRelativeFrame(.horizontal) { width, _ in width * fraction }
                        if index.isMultiple(of: 2) { Spacer(minLength: 0) }
                    }
                }
            }
            .padding(.horizontal, Spacing.medium)
            .padding(.vertical, Spacing.small)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ConversationStrings.text("older.loading"))
        }
    }

    extension TimelineItem {
        /// My own message arriving while the list is on screen: a send from here or another device.
        var isOwnLiveSend: Bool {
            switch self {
            case .message(let row): row.isMine && row.isLiveArrival
            case .pending(let row): row.isLiveArrival
            case .day, .system, .callLog: false
            }
        }
    }

    /// Bubble-shaped placeholders while the first page loads (shown after ~300 ms).
    struct MessagesSkeleton: View {
        var body: some View {
            GeometryReader { geometry in
                VStack(spacing: Spacing.smallPlus) {
                    Spacer(minLength: 0)
                    ForEach(Array(ChatMetrics.skeletonWidthFractions.enumerated()), id: \.offset) { index, fraction in
                        HStack {
                            if index.isMultiple(of: 2) { Spacer(minLength: 0) }
                            SkeletonBlock(
                                width: geometry.size.width * fraction,
                                height: ChatMetrics.skeletonBubbleHeight,
                                cornerRadius: ChatMetrics.bubbleRadius
                            )
                            if !index.isMultiple(of: 2) { Spacer(minLength: 0) }
                        }
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(ConversationStrings.text("messages.loading"))
        }
    }
#endif
