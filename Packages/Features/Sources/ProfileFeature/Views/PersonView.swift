#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// Another person's profile with a Message button.
    public struct PersonView: View {
        @Environment(\.dataEnvironment) private var data
        let userID: String
        let onOpenConversation: (_ conversationID: Int) -> Void

        public init(
            userID: String,
            onOpenConversation: @escaping (_ conversationID: Int) -> Void
        ) {
            self.userID = userID
            self.onOpenConversation = onOpenConversation
        }

        public var body: some View {
            Group {
                if let data {
                    PersonScreen(
                        model: PersonModel(userID: userID, environment: data),
                        onOpenConversation: onOpenConversation
                    )
                } else {
                    EmptyStateView(
                        systemImage: "person.crop.circle.badge.exclamationmark",
                        title: ProfileStrings.personErrorTitle
                    )
                }
            }
            .background(Palette.background)
            .navigationTitle(ProfileStrings.personTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
    }

    private struct PersonScreen: View {
        @State private var model: PersonModel
        @State private var messageRequest = 0
        @State private var retryRequest = 0
        /// Which button opened the chat, so only that one says "Opening chat…".
        @State private var wishesTapped = false
        let onOpenConversation: (_ conversationID: Int) -> Void

        init(model: PersonModel, onOpenConversation: @escaping (_ conversationID: Int) -> Void) {
            _model = State(initialValue: model)
            self.onOpenConversation = onOpenConversation
        }

        var body: some View {
            PersonContentView(
                state: PersonDisplayState(model: model, wishesTapped: wishesTapped),
                onRetry: { retryRequest += 1 },
                onMessage: {
                    wishesTapped = false
                    messageRequest += 1
                },
                onSendWishes: {
                    wishesTapped = true
                    messageRequest += 1
                },
                onDismissError: { model.dismissMessageError() }
            )
            .refreshable { await model.load() }
            .task { await model.run() }
            .task(id: retryRequest) {
                guard retryRequest > 0 else { return }
                await model.load()
            }
            .task(id: messageRequest) {
                guard messageRequest > 0 else { return }
                if let conversationID = await model.message() {
                    onOpenConversation(conversationID)
                }
            }
        }
    }

    struct PersonDisplayState {
        var phase: PersonModel.Phase
        var userID: String
        var name: String?
        var celebration: Celebration?
        var canMessage: Bool
        var isOpeningChat = false
        var wishesTapped = false
        var messageError: WaiveraError?

        @MainActor
        init(model: PersonModel, wishesTapped: Bool = false) {
            phase = model.phase
            userID = model.userID
            name = model.displayName
            celebration = model.celebration
            canMessage = model.canMessage
            isOpeningChat = model.isOpeningChat
            self.wishesTapped = wishesTapped
            messageError = model.messageError
        }

        init(
            phase: PersonModel.Phase,
            userID: String,
            name: String?,
            canMessage: Bool = true,
            celebration: Celebration? = nil
        ) {
            self.phase = phase
            self.userID = userID
            self.name = name
            self.canMessage = canMessage
            self.celebration = celebration
        }

        var email: String? {
            if case .loaded(let person) = phase { return person.email?.nonBlank }
            return nil
        }
    }

    /// The person page for one state. Stateless: previews and snapshots build it directly.
    struct PersonContentView: View {
        let state: PersonDisplayState
        let onRetry: () -> Void
        let onMessage: () -> Void
        var onSendWishes: () -> Void = {}
        let onDismissError: () -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    // The bar names the screen and the hero names the person, so the name is
                    // not said twice.
                    HeroSection(trail: .none) {
                        EmptyView()
                    } content: {
                        PersonHero(state: state)
                    }
                    VStack(alignment: .leading, spacing: Spacing.mediumSmall) {
                        if state.canMessage {
                            PersonActions(
                                name: name,
                                celebrating: state.celebration != nil,
                                isOpeningChat: state.isOpeningChat,
                                wishesTapped: state.wishesTapped,
                                onMessage: onMessage,
                                onSendWishes: onSendWishes
                            )
                        }
                        if let error = state.messageError {
                            BannerView(
                                .error,
                                message: ProfileStrings.personMessageFailed + " " + error.userMessage,
                                onDismiss: onDismissError
                            )
                        }
                        details
                    }
                    .padding(.horizontal, Spacing.medium)
                    .padding(.bottom, Spacing.large)
                }
            }
        }

        private var name: String { state.name ?? ProfileStrings.unknownPerson }

        @ViewBuilder private var details: some View {
            switch state.phase {
            case .loading:
                LoadingContent(isLoading: true) {
                    EmptyView()
                } skeleton: {
                    SkeletonBlock(height: ControlSize.buttonHeight * 3, cornerRadius: Radius.listCard)
                }
            case .failed(let error):
                EmptyStateView.error(
                    title: ProfileStrings.personErrorTitle,
                    message: error.userMessage,
                    onRetry: onRetry
                )
            case .loaded(let person):
                // Absent values are left out here (06 §C2): this card describes someone else, not
                // a form to fill. The own profile shows "—" instead.
                let candidates = [
                    PersonDetail(ProfileStrings.organizationTitle, person.organizationName, "building.2"),
                    PersonDetail(ProfileStrings.personRoles, ProfileText.joined(person.roles), "person.text.rectangle"),
                    PersonDetail(ProfileStrings.phone, person.phoneNumber?.nonBlank, "phone"),
                ]
                let rows = candidates.filter { $0.value != nil }
                if !rows.isEmpty {
                    SectionCard {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { RowDivider(underTile: true) }
                            DetailRow(label: row.label, value: row.value ?? "", systemImage: row.image)
                        }
                    }
                }
            }
        }
    }

    /// The person on the plum hero, centred: the large avatar, their name and address, and
    /// today's celebration greeting them by first name.
    private struct PersonHero: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let state: PersonDisplayState

        var body: some View {
            let name = state.name ?? ProfileStrings.unknownPerson
            VStack(spacing: Spacing.small) {
                PersonAvatar(
                    userID: state.userID,
                    name: name,
                    size: CGFloat(
                        dynamicTypeSize.isLargeText ? HeroMetrics.profileAvatarCompact : HeroMetrics.profileAvatar
                    ),
                    celebration: state.celebration
                )
                .accessibilityHidden(true)
                if state.name == nil, state.phase == .loading {
                    SkeletonBlock(width: Spacing.huge * 4)
                } else {
                    NameText(name, style: .heroGreetingCompact, lines: NameLines.hero(dynamicTypeSize.category))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(HeroPalette.onHeader)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("person.hero.name")
                }
                if let email = state.email {
                    Text(email)
                        .waiveraTextStyle(.bodyMedium)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(HeroPalette.onHeaderSecondary)
                        .textSelection(.enabled)
                }
                if let celebration = state.celebration {
                    // The name is right above, so the note says only the first name.
                    HeroCelebrationNote(
                        emoji: ProfileStrings.celebrationEmoji(celebration),
                        text: ProfileStrings.celebrationHero(
                            celebration,
                            firstName: ProfileText.firstName(of: state.name)
                        )
                    )
                    .padding(.top, Spacing.extraSmall)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, Spacing.medium)
            .padding(.bottom, Spacing.medium)
        }
    }

    /// Message, always the primary, so the screen's action is the same whether or not it is their
    /// day. On their birthday or anniversary "Send wishes" sits beside it as the raised secondary;
    /// both open the same direct chat and the one tapped shows the busy label. Above 130% text
    /// the two stack, so neither label wraps.
    private struct PersonActions: View {
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        let name: String
        let celebrating: Bool
        let isOpeningChat: Bool
        let wishesTapped: Bool
        let onMessage: () -> Void
        let onSendWishes: () -> Void

        var body: some View {
            if !celebrating {
                message
            } else if dynamicTypeSize.isLargeText {
                VStack(spacing: Spacing.small) {
                    message
                    wishes
                }
            } else {
                HStack(spacing: Spacing.small) {
                    message
                    wishes
                }
            }
        }

        private var message: some View {
            WaiveraButton(
                ProfileStrings.personMessage,
                systemImage: "bubble.left.fill",
                isLoading: isOpeningChat && !wishesTapped,
                loadingTitle: ProfileStrings.personOpeningChat,
                fillsWidth: true,
                action: onMessage
            )
            .disabled(isOpeningChat)
            .accessibilityLabel(Text(ProfileStrings.personMessageSpoken(name)))
            .accessibilityIdentifier("person.message")
        }

        private var wishes: some View {
            WaiveraButton(
                ProfileStrings.personSendWishes,
                variant: .secondary,
                isLoading: isOpeningChat && wishesTapped,
                loadingTitle: ProfileStrings.personOpeningChat,
                fillsWidth: true,
                action: onSendWishes
            )
            .disabled(isOpeningChat)
            .accessibilityLabel(Text(ProfileStrings.personSendWishesSpoken(name)))
            .accessibilityIdentifier("person.sendWishes")
        }
    }

    #if DEBUG
        @MainActor private func personPreview() -> PersonDisplayState {
            let data = DemoData.make()
            let person =
                data.people.values.sorted { $0.id < $1.id }.first
                ?? PersonProfile(id: "usr_jordan_lee", displayName: "Jordan Lee")
            return PersonDisplayState(phase: .loaded(person), userID: person.id, name: person.displayName)
        }

        #Preview("Light") {
            NavigationStack { PersonView(userID: "usr_priya_raman", onOpenConversation: { _ in }) }
                .fakeDataEnvironment()
        }
        #Preview("Dark") {
            NavigationStack {
                PersonContentView(state: personPreview(), onRetry: {}, onMessage: {}, onDismissError: {})
            }
            .preferredColorScheme(.dark)
        }
        #Preview("AX XXXL") {
            NavigationStack {
                PersonContentView(state: personPreview(), onRetry: {}, onMessage: {}, onDismissError: {})
            }
            .dynamicTypeSize(.accessibility5)
        }
    #endif

    /// One detail on a person's card; rows with no value are left out.
    private struct PersonDetail {
        let label: String
        let value: String?
        let image: String

        init(_ label: String, _ value: String?, _ image: String) {
            self.label = label
            self.value = value
            self.image = image
        }
    }
#endif
