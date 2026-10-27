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

    /// The inbox, stateless apart from presentation timing. The header (status pill and filter)
    /// is the list's first row; while it is on screen the person is at the top and rows reorder
    /// live. Scrolled down, the model holds the order and the "New activity" pill appears, so
    /// a realtime reorder never moves what the person is reading.
    struct ChatListContentView: View {
        let state: ChatListState
        @Binding var query: String
        @Binding var filter: ChatListFilter
        let avatar: (String) -> Image?
        let actions: ChatListActions

        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isSkeletonVisible: Bool

        private static let headerID = "chatList.header"

        /// `showsSkeletonImmediately` skips the ~300 ms delay, for snapshot tests only.
        init(
            state: ChatListState,
            query: Binding<String>,
            filter: Binding<ChatListFilter>,
            avatar: @escaping (String) -> Image? = { _ in nil },
            actions: ChatListActions = ChatListActions(),
            showsSkeletonImmediately: Bool = false
        ) {
            self.state = state
            _query = query
            _filter = filter
            self.avatar = avatar
            self.actions = actions
            _isSkeletonVisible = State(initialValue: showsSkeletonImmediately)
        }

        var body: some View {
            ScrollViewReader { proxy in
                List {
                    header
                        .id(Self.headerID)
                        .onAppear { actions.onTopVisibilityChange(true) }
                        .onDisappear { actions.onTopVisibilityChange(false) }
                    content
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
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
                        .transition(Motion.transition(edge: .top, reduceMotion: reduceMotion))
                    }
                }
                .overlay(alignment: .bottom) { noticeBanner }
                .animation(Motion.animation(.state, reduceMotion: reduceMotion), value: state.hasPendingReorder)
                .animation(Motion.animation(.layout, reduceMotion: reduceMotion), value: state.notice)
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(ChatListStrings.string("chat.list.search.prompt"))
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .skeletonGate(isLoading: state.content == .loading, isVisible: $isSkeletonVisible)
            .waiveraHaptic(.failure, trigger: state.notice?.id) { _, new in new != nil }
        }

        private var header: some View {
            VStack(alignment: .leading, spacing: Spacing.small) {
                ConnectionPill(connection: state.connection)
                    .padding(.horizontal, Spacing.medium)
                SegmentedChips(
                    options: ChatListFilter.allCases.map {
                        SegmentedChips<ChatListFilter>.Option($0, title: Self.title(for: $0))
                    },
                    selection: $filter
                )
            }
            .padding(.vertical, Spacing.small)
            .listRowInsets(EdgeInsets())
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.background)
        }

        @ViewBuilder private var content: some View {
            if isSkeletonVisible || state.content == .loading {
                if isSkeletonVisible {
                    SkeletonList(rows: 6)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Palette.background)
                }
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
                    if let error = state.refreshError { refreshBanner(error) }
                    stateRow(emptyState(reason))
                case .rows:
                    if let error = state.refreshError { refreshBanner(error) }
                    ForEach(state.rows) { row in
                        rowView(row)
                    }
                }
            }
        }

    }

    extension ChatListContentView {
        @ViewBuilder private func markReadSwipe(_ row: ChatRow) -> some View {
            if row.isUnread {
                Button {
                    actions.onMarkRead(row.id)
                } label: {
                    Label(ChatListStrings.string("chat.list.action.markRead"), systemImage: "envelope.open.fill")
                }
                .tint(Palette.accent)
            }
        }

        private func rowView(_ row: ChatRow) -> some View {
            ConversationRowView(
                row: row,
                avatar: row.profileUserId.flatMap(avatar),
                onJoinCall: { actions.onJoinCall(row.id) }
            )
            .contentShape(Rectangle())
            .onTapGesture { actions.onOpen(row.id) }
            .listRowInsets(EdgeInsets(top: 0, leading: Spacing.medium, bottom: 0, trailing: Spacing.medium))
            .listRowSeparatorTint(Palette.border)
            .listRowBackground(
                ZStack {
                    row.isUnread ? Palette.accentWash : Palette.background
                    ArrivalWash(key: row.arrivalKey)
                }
            )
            .swipeActions(edge: .leading, allowsFullSwipe: true) { markReadSwipe(row) }
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                if row.isCallLive {
                    Button {
                        actions.onJoinCall(row.id)
                    } label: {
                        Label(ChatListStrings.string("chat.list.call.joinAction"), systemImage: "video.fill")
                    }
                    .tint(Palette.success)
                }
                if let userId = row.profileUserId {
                    Button {
                        actions.onViewProfile(userId)
                    } label: {
                        Label(ChatListStrings.string("chat.list.action.profile"), systemImage: "person.crop.circle")
                    }
                    .tint(Palette.textSecondary)
                }
            }
            .contextMenu { rowMenu(row) }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(row.accessibilityText))
            .accessibilityValue(Text(Self.details(for: row)))
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { actions.onOpen(row.id) }
            .accessibilityActions { rowMenu(row) }
            .accessibilityIdentifier("chatList.row.\(row.id)")
        }

        /// The button alternatives to every swipe action: long press and VoiceOver actions.
        @ViewBuilder private func rowMenu(_ row: ChatRow) -> some View {
            Button {
                actions.onOpen(row.id)
            } label: {
                Label(ChatListStrings.string("chat.list.action.open"), systemImage: "bubble.left")
            }
            if row.isUnread {
                Button {
                    actions.onMarkRead(row.id)
                } label: {
                    Label(ChatListStrings.string("chat.list.action.markRead"), systemImage: "envelope.open")
                }
            }
            if row.isCallLive {
                Button {
                    actions.onJoinCall(row.id)
                } label: {
                    Label(ChatListStrings.string("chat.list.call.joinAction"), systemImage: "video")
                }
            }
            if let userId = row.profileUserId {
                Button {
                    actions.onViewProfile(userId)
                } label: {
                    Label(ChatListStrings.string("chat.list.action.profile"), systemImage: "person.crop.circle")
                }
            }
        }

        private func refreshBanner(_ error: WaiveraError) -> some View {
            BannerView(
                .error,
                message: ChatListStrings.format("chat.list.refreshFailed", error.userMessage),
                actionTitle: ChatListStrings.string("chat.list.retry"),
                action: actions.onRetryLoad
            )
            .listRowInsets(
                EdgeInsets(top: Spacing.small, leading: Spacing.medium, bottom: Spacing.small, trailing: Spacing.medium)
            )
            .listRowSeparator(.hidden)
            .listRowBackground(Palette.background)
        }

        private func stateRow(_ view: EmptyStateView) -> some View {
            view
                .padding(.top, Spacing.extraLarge)
                .listRowInsets(EdgeInsets())
                .listRowSeparator(.hidden)
                .listRowBackground(Palette.background)
        }

        private func emptyState(_ reason: ChatListEmptyReason) -> EmptyStateView {
            let keys: (title: String, message: String) =
                switch reason {
                case .noMatches: ("chat.list.empty.search.title", "chat.list.empty.search")
                case .allCaughtUp: ("chat.list.empty.unread.title", "chat.list.empty.unread")
                case .noChannels: ("chat.list.empty.channels.title", "chat.list.empty.channels")
                case .noConversations: ("chat.list.empty.title", "chat.list.empty")
                }
            let offersNewChat = reason == .noConversations
            return EmptyStateView(
                systemImage: reason == .allCaughtUp ? "checkmark.circle.fill" : "bubble.left.and.bubble.right",
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
                .padding(Spacing.medium)
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

    #if DEBUG
        private struct ContentPreview: View {
            let state: ChatListState
            @State private var query = ""
            @State private var filter = ChatListFilter.all

            var body: some View {
                NavigationStack {
                    ChatListContentView(state: state, query: $query, filter: $filter)
                        .navigationTitle(ChatListStrings.string("chat.list.title"))
                }
            }
        }

        #Preview("Light, rows") { ContentPreview(state: ChatListPreviewData.state) }
        #Preview("Dark, reconnecting, empty") {
            ContentPreview(state: ChatListPreviewData.state(.empty(.allCaughtUp), connection: .reconnecting))
                .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL, error") {
            ContentPreview(state: ChatListPreviewData.state(.error(.offline), connection: .offline))
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
