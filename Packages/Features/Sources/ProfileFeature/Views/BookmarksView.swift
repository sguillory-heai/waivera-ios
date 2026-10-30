#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

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
        /// The card an Undo brought back draws above its neighbours while they slide out of its
        /// place. Cards never overlap at rest, so it keeps the raise until the next removal.
        @State private var returningID: Int?
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
                state: BookmarksDisplayState(model: model, actionError: actionError, returningID: returningID),
                actions: BookmarksActions(
                    retry: { refreshRequest += 1 },
                    clearSearch: { model.query = "" },
                    selectFilter: { model.filter = $0 },
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
                returningID = nil
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
                returningID = row.messageID
                await model.undoRemove(row)
                if model.restoreError != nil { actionError = ProfileStrings.bookmarksRestoreFailed }
                undoRequest = nil
            }
        }
    }

    struct BookmarksActions {
        var retry: () -> Void = {}
        var clearSearch: () -> Void = {}
        var selectFilter: (BookmarkFilter) -> Void = { _ in }
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
        var filter = BookmarkFilter.all
        var isFiltered = false
        var showsFilterChips = false
        var emptyReason: BookmarksEmptyReason?
        var countRose = true
        var returningID: Int?

        init() {}

        @MainActor
        init(model: BookmarksModel, actionError: String?, returningID: Int? = nil) {
            phase = model.phase
            rows = model.rows
            totalCount = model.totalCount
            isSearching = model.query.nonBlank != nil
            refreshError = model.refreshError
            usedFallback = model.usedFallback
            self.actionError = actionError
            filter = model.filter
            isFiltered = model.isFiltered
            showsFilterChips = model.showsFilterChips
            emptyReason = model.emptyReason
            countRose = model.countRose
            self.returningID = returningID
        }

        /// "3 saved messages", or "1 of 3 shown" while a search or chip narrows the list.
        var countLine: String {
            isFiltered
                ? ProfileStrings.filteredCount(rows.count, of: totalCount) : ProfileStrings.bookmarksCount(totalCount)
        }
    }

    struct BookmarksContentView: View {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
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
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Spacing.small) {
                    notices
                    if state.showsFilterChips {
                        SegmentedChips(
                            options: BookmarkFilter.allCases.map {
                                SegmentedChips<BookmarkFilter>.Option($0, title: ProfileStrings.filter($0))
                            },
                            selection: Binding(get: { state.filter }, set: actions.selectFilter)
                        )
                        .padding(.horizontal, -Spacing.medium)
                        .accessibilityLabel(Text(ProfileStrings.bookmarksFilterLabel))
                    }
                    if state.phase == .noMatches {
                        emptyResult
                    } else {
                        // The count rolls as a bookmark goes: down when it falls, up when it grows.
                        SwapView(state.countLine, axis: .vertical, forward: state.countRose) { line in
                            Text(line)
                                .waiveraTextStyle(.labelMedium)
                                .foregroundStyle(Palette.textSecondary)
                                .padding(.vertical, Spacing.extraSmall)
                        }
                        .clipped()
                    }
                    ForEach(state.rows) { row in
                        BookmarkCard(
                            row: row,
                            now: state.now,
                            onOpen: { actions.open(row) },
                            onRemove: { actions.remove(row) }
                        )
                        .zIndex(state.returningID == row.messageID ? 1 : 0)
                        .transition(Motion.enterAfterExit(reduceMotion: reduceMotion))
                        .accessibilityIdentifier("bookmarks.row.\(row.messageID)")
                    }
                }
                .padding(.horizontal, Spacing.medium)
                .padding(.bottom, Spacing.medium)
                .waiveraAnimation(.layout, value: state.rows.map(\.messageID))
            }
            .scrollDismissesKeyboard(.immediately)
        }

        @ViewBuilder private var emptyResult: some View {
            switch state.emptyReason {
            case .noneInFilter(let filter):
                EmptyStateView(
                    systemImage: "bookmark",
                    title: ProfileStrings.noneInFilterTitle(filter),
                    message: ProfileStrings.noneInFilterMessage(filter),
                    actionTitle: ProfileStrings.bookmarksShowAll,
                    action: { actions.selectFilter(.all) }
                )
                .padding(.top, Spacing.large)
            case .noMatch, nil:
                EmptyStateView(
                    systemImage: "magnifyingglass",
                    title: ProfileStrings.bookmarksNoMatchTitle,
                    message: ProfileStrings.bookmarksNoMatchMessage,
                    actionTitle: ProfileStrings.clearSearch,
                    action: actions.clearSearch
                )
                .padding(.top, Spacing.large)
            }
        }

        @ViewBuilder private var notices: some View {
            if let actionError = state.actionError {
                BannerView(.error, message: actionError, onDismiss: actions.dismissError)
            }
            if state.refreshError != nil {
                RefreshFailedNotice(message: ProfileStrings.bookmarksRefreshFailed, onRetry: actions.retry)
            } else if state.usedFallback {
                BannerView(.info, message: ProfileStrings.bookmarksFallback)
            }
        }
    }

    /// One saved message on a lifted sheet card, led by who wrote it. Remove answers on its own
    /// control first: the glyph changes to the plain bookmark, and the card leaves a beat later.
    /// If the card is still here a while after that, the removal did not hold (it failed, or was
    /// undone at once) and the glyph goes back so it can be tapped again.
    private struct BookmarkCard: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        let row: BookmarkRow
        let now: Date
        let onOpen: () -> Void
        let onRemove: () -> Void
        @State private var removing = false

        @MainActor private static let relative: RelativeDateTimeFormatter = {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return formatter
        }()

        var body: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                Button(action: onOpen) {
                    content
                }
                .buttonStyle(.press(.card))
                .accessibilityLabel(Text(ProfileStrings.bookmarksOpen(author)))
                .accessibilityValue(Text(ProfileStrings.preview(row.preview)))
                removeButton
            }
            .padding(Spacing.mediumSmall)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.sheetCard, style: .continuous))
            .shadow(
                color: Palette.buttonRaise,
                radius: Elevation.shadow(for: Elevation.card).radius,
                x: 0,
                y: Elevation.shadow(for: Elevation.card).y
            )
            .task(id: removing) {
                guard removing else { return }
                if !reduceMotion { try? await Task.sleep(for: .seconds(MotionTiming.removalBeat)) }
                // Asked for even when the card left first (the screen closed), so a tap is never lost.
                onRemove()
                guard !Task.isCancelled else { return }
                try? await Task.sleep(for: .seconds(MotionTiming.removalHeld))
                guard !Task.isCancelled else { return }
                removing = false
            }
        }

        private var author: String { row.author?.nonBlank ?? ProfileStrings.unknownPerson }

        private var content: some View {
            HStack(alignment: .top, spacing: Spacing.mediumSmall) {
                PersonAvatar(userID: row.authorID, name: author)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                    // Capped like other message lists so a long name never takes over the card.
                    NameText(author, style: .titleSmall, lines: NameLines.bookmarkAuthor(dynamicTypeSize.category))
                        .foregroundStyle(Palette.text)
                    if let createdAt = row.createdAt {
                        Text(Self.relative.localizedString(for: createdAt, relativeTo: now))
                            .waiveraTextStyle(.labelSmall)
                            .foregroundStyle(Palette.textSecondary)
                    }
                    Text(ProfileStrings.preview(row.preview))
                        .waiveraTextStyle(.bodyMedium)
                        .foregroundStyle(Palette.text)
                        .lineLimit(2)
                    if row.isThreadReply {
                        StatusBadge(ProfileStrings.bookmarksThreadReply, tone: .neutral)
                    } else if row.isThreadRoot {
                        StatusBadge(ProfileStrings.bookmarksThreadRoot, tone: .neutral)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .contentShape(Rectangle())
        }

        private var removeButton: some View {
            Button {
                removing = true
            } label: {
                Image(systemName: removing ? "bookmark" : "bookmark.fill")
                    .font(WaiveraFont.bodyEmphasis)
                    .foregroundStyle(removing ? Palette.textSecondary : Palette.accent)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.press(.compact))
            .popOnChange(of: removing)
            .disabled(removing)
            .accessibilityLabel(
                Text(removing ? ProfileStrings.bookmarksRemoving : ProfileStrings.bookmarksRemoveSpoken(author))
            )
        }
    }
#endif
