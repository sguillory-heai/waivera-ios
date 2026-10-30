#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Staff directory with search. Rows open the person's profile.
    public struct PeopleView: View {
        @Environment(\.dataEnvironment) private var data
        let onOpenPerson: (_ userID: String) -> Void

        public init(
            onOpenPerson: @escaping (_ userID: String) -> Void
        ) {
            self.onOpenPerson = onOpenPerson
        }

        public var body: some View {
            Group {
                if let data {
                    PeopleScreen(model: PeopleModel(environment: data), onOpenPerson: onOpenPerson)
                } else {
                    PeopleContentView(state: PeopleDisplayState(), onRetry: {}, onOpenPerson: { _ in })
                }
            }
            .background(Palette.background)
            .navigationTitle(ProfileStrings.peopleTitle)
        }
    }

    private struct PeopleScreen: View {
        @State private var model: PeopleModel
        @State private var refreshRequest = 0
        let onOpenPerson: (_ userID: String) -> Void

        init(model: PeopleModel, onOpenPerson: @escaping (_ userID: String) -> Void) {
            _model = State(initialValue: model)
            self.onOpenPerson = onOpenPerson
        }

        var body: some View {
            PeopleContentView(
                state: PeopleDisplayState(model: model),
                onRetry: { refreshRequest += 1 },
                onOpenPerson: onOpenPerson
            )
            .searchable(
                text: $model.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: ProfileStrings.peopleSearch
            )
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .refreshable { await model.refresh() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    RefreshToolbarButton(
                        title: ProfileStrings.peopleRefresh,
                        busyTitle: ProfileStrings.peopleRefresh,
                        isRefreshing: model.isRefreshing
                    ) { refreshRequest += 1 }
                }
            }
            .task { await model.run() }
            .task(id: refreshRequest) {
                guard refreshRequest > 0 else { return }
                await model.refresh()
            }
        }
    }

    struct PeopleDisplayState {
        var phase = ListPhase.loading
        var rows: [PersonRow] = []
        var totalCount = 0
        var isSearching = false
        var refreshError: WaiveraError?

        init() {}

        @MainActor
        init(model: PeopleModel) {
            phase = model.phase
            rows = model.rows
            totalCount = model.totalCount
            isSearching = model.query.nonBlank != nil
            refreshError = model.refreshError
        }
    }

    struct PeopleContentView: View {
        let state: PeopleDisplayState
        let onRetry: () -> Void
        let onOpenPerson: (_ userID: String) -> Void

        var body: some View {
            switch state.phase {
            case .loading:
                LoadingContent(isLoading: true) {
                    EmptyView()
                } skeleton: {
                    ScrollView { SkeletonList() }
                }
            case .failed(let error):
                ScrollView {
                    EmptyStateView.error(
                        title: ProfileStrings.peopleErrorTitle,
                        message: error.userMessage,
                        onRetry: onRetry
                    )
                    .padding(.top, Spacing.extraLarge)
                }
            case .empty:
                ScrollView {
                    EmptyStateView(
                        systemImage: "person.2",
                        title: ProfileStrings.peopleEmptyTitle,
                        message: ProfileStrings.peopleEmptyMessage
                    )
                    .padding(.top, Spacing.extraLarge)
                }
            case .noMatches, .content:
                list
            }
        }

        private var list: some View {
            List {
                if state.refreshError != nil {
                    RefreshFailedNotice(message: ProfileStrings.peopleRefreshFailed, onRetry: onRetry)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                Section {
                    if state.phase == .noMatches {
                        EmptyStateView(
                            systemImage: "magnifyingglass",
                            title: ProfileStrings.peopleNoMatchTitle,
                            message: ProfileStrings.peopleNoMatchMessage
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    }
                    ForEach(state.rows) { row in
                        Button {
                            onOpenPerson(row.id)
                        } label: {
                            PersonListRow(row: row)
                        }
                        .buttonStyle(.press(.card))
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Palette.surface)
                        .accessibilityIdentifier("people.row.\(row.id)")
                    }
                } header: {
                    Text(
                        state.isSearching
                            ? ProfileStrings.filteredCount(state.rows.count, of: state.totalCount)
                            : ProfileStrings.peopleCount(state.totalCount)
                    )
                    .waiveraTextStyle(.labelMedium)
                    .foregroundStyle(Palette.textSecondary)
                    .textCase(nil)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
    }

    private struct PersonListRow: View {
        let row: PersonRow

        var body: some View {
            ListRow(
                title: row.name,
                subtitle: row.celebration.map(ProfileStrings.celebrationCompact),
                titleKind: .personName,
                showsChevron: true
            ) {
                PersonAvatar(userID: row.id, name: row.name, celebration: row.celebration)
            }
            .accessibilityLabel(Text(ProfileStrings.peopleOpen(row.name)))
            .accessibilityAddTraits(.isButton)
        }
    }

    #if DEBUG
        @MainActor private func peoplePreviewState() -> PeopleDisplayState {
            var state = PeopleDisplayState()
            state.phase = .content
            state.rows = DemoData.make().directory.map { PersonRow(id: $0.id, name: $0.name) }
            state.totalCount = state.rows.count
            return state
        }

        #Preview("Light") {
            NavigationStack { PeopleView(onOpenPerson: { _ in }) }.fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack { PeopleContentView(state: peoplePreviewState(), onRetry: {}, onOpenPerson: { _ in }) }
                .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack { PeopleContentView(state: peoplePreviewState(), onRetry: {}, onOpenPerson: { _ in }) }
                .dynamicTypeSize(.accessibility5)
        }
        #Preview("Failed") {
            NavigationStack { PeopleView(onOpenPerson: { _ in }) }.fakeDataEnvironment(.failing)
        }
    #endif
#endif
