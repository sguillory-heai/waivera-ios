#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraAPI
    import WaiveraDesign

    /// Callbacks from the inbox to its owner, grouped so the content stays previewable. All run
    /// on the main actor from view actions; `onRefresh` is sendable because `.refreshable`'s
    /// action is.
    struct ChatListActions {
        var onOpen: (Int) -> Void = { _ in }
        var onNewChat: () -> Void = {}
        var onMarkRead: (Int) -> Void = { _ in }
        var onJoinCall: (Int) -> Void = { _ in }
        var onViewProfile: (String) -> Void = { _ in }
        var onRefresh: @Sendable () async -> Void = {}
        var onRetryLoad: () -> Void = {}
        var onTopVisibilityChange: (Bool) -> Void = { _ in }
        var onShowNewActivity: () -> Void = {}
        var onDismissNotice: () -> Void = {}
        var onRetryNotice: (ChatListNotice) -> Void = { _ in }
    }

    /// The signed-in person on the hero bar; their avatar opens the account menu.
    struct ChatListAccount {
        var name: String
        var image: Image?
        var accessibilityLabel: String?
        var onOpen: () -> Void
    }

    /// The inbox, stateless apart from presentation timing (Android `ChatListContent`): the plum
    /// hero bar with "+", then the page with the header (connecting pill, refresh banner, search
    /// and the filter chips) as the list's first row and the rows on one card. While the header
    /// is on screen the person is at the top and rows reorder live; scrolled down, the model holds
    /// the order and the "New activity" pill appears, so a realtime reorder never moves what the
    /// person is reading.
    struct ChatListContentView: View {
        let state: ChatListState
        @Binding var query: String
        @Binding var filter: ChatListFilter
        let avatar: (String) -> Image?
        let account: ChatListAccount?
        let actions: ChatListActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isSkeletonVisible: Bool
        @State private var isConnectingPillDue: Bool
        @State private var actionsRowId: Int?

        private static let headerID = "chatList.header"

        /// `showsSkeletonImmediately` skips the ~300 ms delay and `showsConnectingPillImmediately`
        /// the 2 s wait before "Connecting", for snapshot tests only.
        init(
            state: ChatListState,
            query: Binding<String>,
            filter: Binding<ChatListFilter>,
            avatar: @escaping (String) -> Image? = { _ in nil },
            account: ChatListAccount? = nil,
            actions: ChatListActions = ChatListActions(),
            showsSkeletonImmediately: Bool = false,
            showsConnectingPillImmediately: Bool = false
        ) {
            self.state = state
            _query = query
            _filter = filter
            self.avatar = avatar
            self.account = account
            self.actions = actions
            _isSkeletonVisible = State(initialValue: showsSkeletonImmediately)
            _isConnectingPillDue = State(
                initialValue: showsConnectingPillImmediately && ChatListHeaderRules.showsConnectingPill(state)
            )
        }

        var body: some View {
            VStack(spacing: 0) {
                HeroSection {
                    HeroTopBar(
                        title: ChatListStrings.string("chat.list.title"),
                        actions: [
                            HeroBarAction(
                                id: "newChat",
                                systemImage: "plus",
                                accessibilityLabel: ChatListStrings.string("chat.list.newChat"),
                                action: actions.onNewChat
                            )
                        ],
                        accountName: account?.name,
                        accountImage: account?.image,
                        accountLabel: account?.accessibilityLabel,
                        onAccount: account?.onOpen
                    )
                } content: {
                    EmptyView()
                }
                list
            }
            .background(Palette.background)
            .skeletonGate(isLoading: state.content == .loading, isVisible: $isSkeletonVisible)
            .task(id: ChatListHeaderRules.showsConnectingPill(state)) { await followConnectingPill() }
            .sheet(item: actionsRow) { row in
                RowActionsSheet(
                    row: row,
                    avatar: row.profileUserId.flatMap(avatar),
                    onOpen: { closeActions { actions.onOpen(row.id) } },
                    onMarkRead: { closeActions { actions.onMarkRead(row.id) } },
                    onJoinCall: { closeActions { actions.onJoinCall(row.id) } },
                    onViewProfile: { userId in closeActions { actions.onViewProfile(userId) } }
                )
                .waiveraSheetPresentation()
            }
        }

        private var list: some View {
            ScrollViewReader { proxy in
                List {
                    header
                        .id(Self.headerID)
                        .onAppear { actions.onTopVisibilityChange(true) }
                        .onDisappear { actions.onTopVisibilityChange(false) }
                        .plainListRow()
                    content
                    Color.clear
                        .frame(height: Spacing.large)
                        .plainListRow()
                        .accessibilityHidden(true)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .environment(\.defaultMinListRowHeight, 0)
                .background(Palette.background)
                .refreshable { [onRefresh = actions.onRefresh] in await onRefresh() }
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: state.rows.map(\.id))
                .overlay(alignment: .top) {
                    if state.hasPendingReorder {
                        NewActivityPill {
                            withAnimation(Motion.animation(.layout, reduceMotion: reduceMotion)) {
                                proxy.scrollTo(Self.headerID, anchor: .top)
                            }
                            actions.onShowNewActivity()
                        }
                        .padding(.top, Spacing.small)
                        .transition(Motion.pop(reduceMotion: reduceMotion))
                    }
                }
                .overlay(alignment: .bottom) { noticeBanner }
                .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: state.hasPendingReorder)
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: state.notice)
            }
        }

        /// One connection signal at a time: the pill only for a slow start-up, the refresh banner
        /// only while connected. Both grow and fold with their gap, so the search field and the
        /// list move smoothly instead of jumping.
        private var header: some View {
            VStack(alignment: .leading, spacing: 0) {
                Expand(isExpanded: isConnectingPillDue) {
                    ConnectionPill(connection: .connecting)
                        .padding(.horizontal, Spacing.gutter)
                        .padding(.bottom, Spacing.mediumSmall)
                }
                Expand(isExpanded: ChatListHeaderRules.showsRefreshBanner(state)) {
                    BannerView(
                        .reconnecting,
                        title: ChatListStrings.string("chat.list.refreshFailed.title"),
                        message: ChatListStrings.string("chat.list.refreshFailed.message"),
                        actionTitle: ChatListStrings.string("chat.list.retry"),
                        action: actions.onRetryLoad
                    )
                    .padding(.horizontal, Spacing.gutter)
                    .padding(.bottom, Spacing.mediumSmall)
                }
                ChatSearchField(
                    label: ChatListStrings.string("chat.list.search.label"),
                    placeholder: ChatListStrings.string("chat.list.search.prompt"),
                    query: $query
                )
                .padding(.horizontal, Spacing.gutter)
                .padding(.bottom, Spacing.mediumSmall)
                // Android `WaiveraSegmentedControl`: the approved filter is a segmented track, not chips.
                SegmentedControl(
                    options: ChatListFilter.allCases.map {
                        SegmentedChips<ChatListFilter>.Option($0, title: Self.title(for: $0))
                    },
                    selection: $filter
                )
                .padding(.horizontal, Spacing.gutter)
                .accessibilityIdentifier("chatList.filter")
            }
            .padding(.bottom, Spacing.mediumSmall)
        }

        @ViewBuilder private var content: some View {
            if isSkeletonVisible {
                ChatListSkeleton()
                    .transition(.opacity.animation(Motion.animation(MotionPolicy.exit(reduceMotion: reduceMotion))))
                    .plainListRow()
            } else {
                switch state.content {
                case .loading:
                    EmptyView()
                case .error(let error):
                    stateRow(
                        EmptyStateView.error(
                            title: ChatListStrings.string("chat.list.error.title"),
                            message: error.userMessage,
                            onRetry: actions.onRetryLoad
                        )
                    )
                case .empty(let reason):
                    stateRow(emptyState(reason))
                case .rows:
                    ForEach(Array(state.rows.enumerated()), id: \.element.id) { index, row in
                        rowView(row, position: InboxCardPosition.of(index: index, count: state.rows.count))
                    }
                }
            }
        }

        private var actionsRow: Binding<ChatRow?> {
            Binding(
                get: { actionsRowId.flatMap { id in state.rows.first { $0.id == id } } },
                set: { if $0 == nil { actionsRowId = nil } }
            )
        }

        private func closeActions(then perform: () -> Void) {
            actionsRowId = nil
            perform()
        }

        /// The quiet "Connecting" pill appears only once start-up has taken longer than the
        /// delay, and folds away as soon as it no longer applies.
        private func followConnectingPill() async {
            guard ChatListHeaderRules.showsConnectingPill(state) else {
                isConnectingPillDue = false
                return
            }
            guard !isConnectingPillDue else { return }
            try? await Task.sleep(for: ChatListHeaderRules.connectingPillDelay)
            guard !Task.isCancelled else { return }
            isConnectingPillDue = true
        }
    }

    extension ChatListContentView {
        private func rowView(_ row: ChatRow, position: InboxCardPosition) -> some View {
            ConversationRowView(
                row: row,
                avatar: row.profileUserId.flatMap(avatar),
                onJoinCall: { actions.onJoinCall(row.id) }
            )
            .background {
                ZStack {
                    Palette.surface
                    ArrivalWash(key: row.arrivalKey)
                }
            }
            .clipShape(position.shape)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(row.accessibilityText))
            .accessibilityValue(Text(Self.details(for: row)))
            .accessibilityActions { rowAccessibilityActions(row) }
            .accessibilityIdentifier("chatList.row.\(row.id)")
            // The row dips and tints under a press; a long press opens the actions sheet.
            .waiveraPressable(
                depth: .row,
                longPressActionName: ChatListStrings.format("chat.list.actions", row.title),
                onTap: { actions.onOpen(row.id) },
                onLongPress: { actionsRowId = row.id }
            )
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.gutter, bottom: 0, trailing: Spacing.gutter))
            .listRowSeparator(.hidden)
            .listRowBackground(InboxCardBackground(position: position))
            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                if row.isUnread {
                    Button {
                        actions.onMarkRead(row.id)
                    } label: {
                        Label(ChatListStrings.string("chat.list.action.markRead"), systemImage: "envelope.open.fill")
                    }
                    .tint(Palette.accentFill)
                }
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if let userId = row.profileUserId {
                    Button {
                        actions.onViewProfile(userId)
                    } label: {
                        Label(ChatListStrings.string("chat.list.action.profile"), systemImage: "person.fill")
                    }
                    .tint(Palette.accentFill)
                }
            }
        }

        /// The swipe actions and the call pill as VoiceOver actions.
        @ViewBuilder private func rowAccessibilityActions(_ row: ChatRow) -> some View {
            if row.isUnread {
                Button(ChatListStrings.string("chat.list.action.markRead")) { actions.onMarkRead(row.id) }
            }
            if row.isCallLive {
                Button(ChatListStrings.string("chat.list.call.joinAction")) { actions.onJoinCall(row.id) }
            }
            if let userId = row.profileUserId {
                Button(ChatListStrings.string("chat.list.action.profile")) { actions.onViewProfile(userId) }
            }
        }

        private func stateRow(_ view: EmptyStateView) -> some View {
            view
                .padding(.top, Spacing.large)
                .transition(Motion.enterAfterExit(reduceMotion: reduceMotion))
                .plainListRow()
        }

        private func emptyState(_ reason: ChatListEmptyReason) -> EmptyStateView {
            let keys: (title: String, message: String) =
                switch reason {
                case .noMatches: ("chat.list.empty.search.title", "chat.list.empty.search")
                case .allCaughtUp: ("chat.list.empty.unread.title", "chat.list.empty.unread")
                case .noChannels: ("chat.list.empty.channels.title", "chat.list.empty.channels")
                case .noConversations: ("chat.list.empty.title", "chat.list.empty")
                }
            let illustration: Illustration =
                switch reason {
                case .noMatches: .search
                case .allCaughtUp: .caughtUp
                case .noChannels: .connections
                case .noConversations: .chats
                }
            let offersNewChat = reason == .noConversations
            return EmptyStateView(
                illustration: illustration,
                title: ChatListStrings.string(keys.title),
                message: ChatListStrings.string(keys.message),
                actionTitle: offersNewChat ? ChatListStrings.string("chat.list.empty.action") : nil,
                action: offersNewChat ? actions.onNewChat : nil
            )
        }

        @ViewBuilder private var noticeBanner: some View {
            if let notice = state.notice {
                BannerView(
                    .error,
                    message: ChatListStrings.string(notice.messageKey),
                    actionTitle: ChatListStrings.string("chat.list.retry"),
                    action: { actions.onRetryNotice(notice) },
                    onDismiss: actions.onDismissNotice
                )
                .padding(Spacing.gutter)
                .transition(Motion.transition(edge: .bottom, reduceMotion: reduceMotion))
                .task(id: notice.id) {
                    let message = ChatListStrings.string(notice.messageKey)
                    UIAccessibility.post(notification: .announcement, argument: message)
                    let lifetime =
                        UIAccessibility.isVoiceOverRunning
                        ? FeedbackTiming.undoToastAccessible : FeedbackTiming.inAppBanner
                    try? await Task.sleep(for: .seconds(lifetime))
                    if !Task.isCancelled { actions.onDismissNotice() }
                }
            }
        }

        /// Kind, read-only and attachment, spoken after the row's label so colour and icons
        /// are never the only signal.
        private static func details(for row: ChatRow) -> String {
            var parts: [String] = []
            switch row.leading {
            case .channel(let archived):
                parts.append(ChatListStrings.string(archived ? "chat.list.icon.archived" : "chat.list.icon.channel"))
            case .bot: parts.append(ChatListStrings.string("chat.list.icon.bot"))
            case .group: parts.append(ChatListStrings.string("chat.list.icon.group"))
            case .direct: break
            }
            if row.isReadOnly { parts.append(ChatListStrings.string("chat.list.readOnly")) }
            if row.hasAttachment { parts.append(ChatListStrings.string("chat.list.attachment")) }
            return parts.joined(separator: ", ")
        }

        private static func title(for filter: ChatListFilter) -> String {
            switch filter {
            case .all: ChatListStrings.string("chat.list.filter.all")
            case .unread: ChatListStrings.string("chat.list.filter.unread")
            case .channels: ChatListStrings.string("chat.list.filter.channels")
            }
        }
    }

    extension View {
        /// A full-bleed list row on the page colour, with no system separator.
        func plainListRow() -> some View {
            listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Palette.background)
        }
    }

    #if DEBUG
        struct ChatListContentPreview: View {
            let state: ChatListState
            var showsSkeleton = false
            @State private var query = ""
            @State private var filter = ChatListFilter.all

            var body: some View {
                NavigationStack {
                    ChatListContentView(
                        state: state,
                        query: $query,
                        filter: $filter,
                        account: ChatListAccount(name: "Alex Rivera", onOpen: {}),
                        showsSkeletonImmediately: showsSkeleton,
                        showsConnectingPillImmediately: true
                    )
                    .toolbar(.hidden, for: .navigationBar)
                }
            }
        }

        #Preview("Light, rows") { ChatListContentPreview(state: ChatListPreviewData.state) }
        #Preview("Dark, caught up, connecting") {
            ChatListContentPreview(state: ChatListPreviewData.state(.empty(.allCaughtUp), connection: .connecting))
                .preferredColorScheme(.dark)
        }
        #Preview("AX5, long names") {
            ChatListContentPreview(state: ChatListPreviewData.longNames)
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("Light, skeleton") {
            ChatListContentPreview(state: ChatListPreviewData.state(.loading), showsSkeleton: true)
        }
        #Preview("Light, error") {
            ChatListContentPreview(state: ChatListPreviewData.state(.error(.offline), connection: .offline))
        }
    #endif
#endif
