#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Saved messages. Thread bookmarks open the thread by its root id (11-pitfalls #21).
    public struct BookmarksView: View {
        @Environment(\.dataEnvironment) private var data
        let onOpenMessage: (_ conversationID: Int, _ messageID: Int, _ threadRootMessageID: Int?) -> Void

        public init(
            onOpenMessage: @escaping (_ conversationID: Int, _ messageID: Int, _ threadRootMessageID: Int?) -> Void
        ) {
            self.onOpenMessage = onOpenMessage
        }

        public var body: some View {
            Group {
                if let data {
                    BookmarksScreen(model: BookmarksModel(environment: data), onOpenMessage: onOpenMessage)
                } else {
                    BookmarksContentView(state: BookmarksDisplayState(), actions: BookmarksActions())
                }
            }
            .background(Palette.background)
            .navigationTitle(ProfileStrings.bookmarksTitle)
        }
    }

    private struct BookmarksScreen: View {
        @State private var model: BookmarksModel
        @State private var refreshRequest = 0
        @State private var removeRequest: BookmarkRow?
        @State private var undoRequest: BookmarkRow?
        @State private var lastRemoved: BookmarkRow?
        @State private var toast: UndoToastItem?
        @State private var actionError: String?
        let onOpenMessage: (_ conversationID: Int, _ messageID: Int, _ threadRootMessageID: Int?) -> Void

        init(
            model: BookmarksModel,
            onOpenMessage: @escaping (_ conversationID: Int, _ messageID: Int, _ threadRootMessageID: Int?) -> Void
        ) {
            _model = State(initialValue: model)
            self.onOpenMessage = onOpenMessage
        }

        var body: some View {
            BookmarksContentView(
                state: BookmarksDisplayState(model: model, actionError: actionError),
                actions: BookmarksActions(
                    retry: { refreshRequest += 1 },
                    clearSearch: { model.query = "" },
                    open: { row in onOpenMessage(row.conversationID, row.messageID, row.threadRootID) },
                    remove: { row in removeRequest = row },
                    dismissError: {
                        actionError = nil
                        model.dismissRestoreError()
                    }
                )
            )
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: ProfileStrings.bookmarksSearch
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .refreshable { await model.refresh() }
            .undoToast(item: $toast) { _ in undoRequest = lastRemoved }
            .task {
                model.searchWords = ProfileStrings.searchWords
                await model.run()
            }
            .task(id: refreshRequest) {
                guard refreshRequest > 0 else { return }
                await model.refresh()
            }
            .task(id: removeRequest) {
                guard let row = removeRequest else { return }
                switch await model.remove(row) {
                case .removed:
                    lastRemoved = row
                    toast = UndoToastItem(message: ProfileStrings.bookmarksRemoved)
                case .failed:
                    actionError = ProfileStrings.bookmarksRemoveFailed
                case .ignored:
                    break
                }
                removeRequest = nil
            }
            .task(id: undoRequest) {
                guard let row = undoRequest else { return }
                await model.undoRemove(row)
                if model.restoreError != nil { actionError = ProfileStrings.bookmarksRestoreFailed }
                undoRequest = nil
            }
        }
    }

    struct BookmarksActions {
        var retry: () -> Void = {}
        var clearSearch: () -> Void = {}
        var open: (BookmarkRow) -> Void = { _ in }
        var remove: (BookmarkRow) -> Void = { _ in }
        var dismissError: () -> Void = {}
    }

    struct BookmarksDisplayState {
        var phase = ListPhase.loading
        var rows: [BookmarkRow] = []
        var totalCount = 0
        var isSearching = false
        var refreshError: WaiveraError?
        var usedFallback = false
        var actionError: String?
        var now = Date()

        init() {}

        @MainActor
        init(model: BookmarksModel, actionError: String?) {
            phase = model.phase
            rows = model.rows
            totalCount = model.totalCount
            isSearching = model.query.nonBlank != nil
            refreshError = model.refreshError
            usedFallback = model.usedFallback
            self.actionError = actionError
        }
    }

    struct BookmarksContentView: View {
        let state: BookmarksDisplayState
        let actions: BookmarksActions

        var body: some View {
            switch state.phase {
            case .loading:
                LoadingContent(isLoading: true) {
                    EmptyView()
                } skeleton: {
                    ScrollView { SkeletonList() }
                }
            case .failed:
                // The raw error is never shown here (06 §B3); it is mapped and logged by the data layer.
                ScrollView {
                    EmptyStateView.error(
                        title: ProfileStrings.bookmarksErrorTitle,
                        message: ProfileStrings.bookmarksErrorMessage,
                        onRetry: actions.retry
                    )
                    .padding(.top, Spacing.extraLarge)
                }
            case .empty:
                ScrollView {
                    EmptyStateView(
                        systemImage: "bookmark",
                        title: ProfileStrings.bookmarksEmptyTitle,
                        message: ProfileStrings.bookmarksEmptyMessage
                    )
                    .padding(.top, Spacing.extraLarge)
                }
            case .noMatches, .content:
                list
            }
        }

        private var list: some View {
            List {
                notices
                Section {
                    if state.phase == .noMatches {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: ProfileStrings.bookmarksNoMatchTitle,
                            message: ProfileStrings.bookmarksNoMatchMessage,
                            actionTitle: ProfileStrings.clearSearch,
                            action: actions.clearSearch
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    ForEach(state.rows) { row in
                        Button {
                            actions.open(row)
                        } label: {
                            BookmarkRowView(row: row, now: state.now)
                        }
                        .buttonStyle(.pressScale)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Palette.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                actions.remove(row)
                            } label: {
                                Label(ProfileStrings.bookmarksRemove, systemImage: "bookmark.slash")
                            }
                        }
                        .accessibilityAction(named: Text(ProfileStrings.bookmarksRemoveSpoken(author(row)))) {
                            actions.remove(row)
                        }
                        .accessibilityIdentifier("bookmarks.row.\(row.messageID)")
                    }
                } header: {
                    Text(
                        state.isSearching
                            ? ProfileStrings.filteredCount(state.rows.count, of: state.totalCount)
                            : ProfileStrings.bookmarksCount(state.totalCount)
                    )
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.textSecondary)
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
            .waiveraHaptic(.failure, trigger: state.actionError) { _, new in new != nil }
        }

        @ViewBuilder private var notices: some View {
            if let actionError = state.actionError {
                BannerView(.error, message: actionError, onDismiss: actions.dismissError)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            if state.refreshError != nil {
                RefreshFailedNotice(message: ProfileStrings.bookmarksRefreshFailed, onRetry: actions.retry)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            } else if state.usedFallback {
                BannerView(.info, message: ProfileStrings.bookmarksFallback)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
        }

        private func author(_ row: BookmarkRow) -> String {
            row.author ?? ProfileStrings.unknownPerson
        }
    }

    private struct BookmarkRowView: View {
        let row: BookmarkRow
        let now: Date

        @MainActor private static let relative: RelativeDateTimeFormatter = {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter
        }()

        var body: some View {
            let author = row.author ?? ProfileStrings.unknownPerson
            HStack(alignment: .top, spacing: Spacing.smallPlus) {
                IconTile(systemImage: "bookmark.fill")
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: Spacing.small) {
                            authorText(author).frame(maxWidth: .infinity, alignment: .leading)
                            timestamp
                        }
                        VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                            authorText(author)
                            timestamp
                        }
                    }
                    Text(ProfileStrings.preview(row.preview))
                        .font(WaiveraFont.body)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                        .truncationMode(.tail)
                    HStack(spacing: Spacing.small) {
                        if row.isThreadReply {
                            StatusBadge(
                                ProfileStrings.bookmarksThreadReply,
                                tone: .neutral,
                                systemImage: "arrowshape.turn.up.left.fill"
                            )
                        }
                        StatusBadge(ProfileStrings.bookmarksSaved, systemImage: "bookmark.fill")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.right")
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(Spacing.smallPlus)
            .frame(minHeight: ControlSize.minHitTarget)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(ProfileStrings.bookmarksOpen(author)))
            .accessibilityValue(Text(ProfileStrings.preview(row.preview)))
            .accessibilityAddTraits(.isButton)
        }

        private func authorText(_ author: String) -> some View {
            Text(author)
                .font(WaiveraFont.bodyEmphasis)
                .foregroundStyle(Palette.text)
                .lineLimit(1)
        }

        @ViewBuilder private var timestamp: some View {
            if let createdAt = row.createdAt {
                Text(Self.relative.localizedString(for: createdAt, relativeTo: now))
                    .font(WaiveraFont.caption)
                    .foregroundStyle(Palette.textSecondary)
            }
        }
    }

    #if DEBUG
        @MainActor private func bookmarksPreview() -> BookmarksDisplayState {
            var state = BookmarksDisplayState()
            state.rows = BookmarkRules.rows(DemoData.make().bookmarks)
            state.totalCount = state.rows.count
            state.phase = state.rows.isEmpty ? .empty : .content
            state.now = DemoData.now
            return state
        }

        #Preview("Light") {
            NavigationStack { BookmarksView(onOpenMessage: { _, _, _ in }) }.fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { BookmarksContentView(state: bookmarksPreview(), actions: BookmarksActions()) }
                .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack { BookmarksContentView(state: bookmarksPreview(), actions: BookmarksActions()) }
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("Empty") {
            NavigationStack { BookmarksView(onOpenMessage: { _, _, _ in }) }.fakeDataEnvironment(.empty)
        }
    #endif
#endif
