#if canImport(UIKit)
    import SwiftUI
    import WaiveraDesign

    /// The message list, anchored to the bottom (11 pitfalls: no manual offsets). Pages older
    /// rows when the top is reached, keeps the newest row in view while the reader is at the
    /// bottom, offers "Jump to latest" when they are not, and runs the screen's scroll commands.
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

        private static var bottomId: String { "timeline-bottom" }
        private var isAtLatest: Bool {
            bottomVisibleId == nil || bottomVisibleId == Self.bottomId || bottomVisibleId == items.last?.id
        }

        var body: some View {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        header()
                        if hasOlder || isLoadingOlder {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: ControlSize.minHitTarget)
                                .accessibilityLabel(ConversationStrings.text("older.loading"))
                                .onAppear(perform: onLoadOlder)
                        }
                        ForEach(items) { item in
                            TimelineItemView(item: item, context: context, actions: actions)
                        }
                        Color.clear.frame(height: Spacing.small).id(Self.bottomId)
                    }
                    .scrollTargetLayout()
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
                .onAppear { run(scrollCommand, proxy) }
            }
        }

        private func jumpButton(_ action: @escaping () -> Void) -> some View {
            Button(action: action) {
                Label(ConversationStrings.text("jump.to.latest"), systemImage: "arrow.down")
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.onAccent)
                    .padding(.horizontal, Spacing.medium)
                    .frame(minHeight: ControlSize.minHitTarget)
                    .background(Palette.accent, in: Capsule())
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
