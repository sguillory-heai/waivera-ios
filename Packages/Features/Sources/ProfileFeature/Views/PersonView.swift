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
        }
    }

    private struct PersonScreen: View {
        @State private var model: PersonModel
        @State private var messageRequest = 0
        @State private var retryRequest = 0
        let onOpenConversation: (_ conversationID: Int) -> Void

        init(model: PersonModel, onOpenConversation: @escaping (_ conversationID: Int) -> Void) {
            _model = State(initialValue: model)
            self.onOpenConversation = onOpenConversation
        }

        var body: some View {
            PersonContentView(
                state: PersonDisplayState(model: model),
                onRetry: { retryRequest += 1 },
                onMessage: { messageRequest += 1 },
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
        var messageError: WaiveraError?

        @MainActor
        init(model: PersonModel) {
            phase = model.phase
            userID = model.userID
            name = model.displayName
            celebration = model.celebration
            canMessage = model.canMessage
            isOpeningChat = model.isOpeningChat
            messageError = model.messageError
        }

        init(phase: PersonModel.Phase, userID: String, name: String?, canMessage: Bool = true) {
            self.phase = phase
            self.userID = userID
            self.name = name
            self.canMessage = canMessage
        }
    }

    struct PersonContentView: View {
        let state: PersonDisplayState
        let onRetry: () -> Void
        let onMessage: () -> Void
        let onDismissError: () -> Void

        var body: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    hero
                    if state.canMessage {
                        WaiveraButton(
                            ProfileStrings.personMessage,
                            systemImage: "bubble.left.fill",
                            isLoading: state.isOpeningChat,
                            action: onMessage
                        )
                        .disabled(state.isOpeningChat)
                        .accessibilityLabel(Text(ProfileStrings.personMessageSpoken(name)))
                        .accessibilityIdentifier("person.message")
                    }
                    if state.messageError != nil {
                        BannerView(
                            .error,
                            message: ProfileStrings.personMessageFailed + " " + (state.messageError?.userMessage ?? ""),
                            onDismiss: onDismissError
                        )
                    }
                    details
                }
                .padding(Spacing.medium)
            }
            .waiveraHaptic(.failure, trigger: state.messageError) { _, new in new != nil }
        }

        private var name: String { state.name ?? ProfileStrings.unknownPerson }

        private var hero: some View {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Spacing.medium) {
                    avatar; identity
                }
                VStack(alignment: .leading, spacing: Spacing.smallPlus) {
                    avatar; identity
                }
            }
        }

        private var avatar: some View {
            PersonAvatar(
                userID: state.userID,
                name: name,
                size: ControlSize.avatarLarge,
                celebration: state.celebration
            )
        }

        private var identity: some View {
            VStack(alignment: .leading, spacing: Spacing.extraSmall) {
                if state.name == nil, state.phase == .loading {
                    SkeletonBlock().frame(maxWidth: Spacing.huge * 4)
                } else {
                    Text(name)
                        .font(WaiveraFont.screenTitle)
                        .foregroundStyle(Palette.text)
                        .accessibilityAddTraits(.isHeader)
                }
                if case .loaded(let person) = state.phase, let email = person.email {
                    Text(email)
                        .font(WaiveraFont.subtitle)
                        .foregroundStyle(Palette.textSecondary)
                        .textSelection(.enabled)
                }
                if let celebration = state.celebration {
                    Label(
                        ProfileStrings.celebrationSentence(celebration, name: state.name),
                        systemImage: "party.popper.fill"
                    )
                    .font(WaiveraFont.captionEmphasis)
                    .foregroundStyle(Palette.milestone)
                }
            }
        }

        @ViewBuilder private var details: some View {
            switch state.phase {
            case .loading:
                LoadingContent(isLoading: true) {
                    EmptyView()
                } skeleton: {
                    SkeletonBlock(height: ControlSize.buttonHeight * 3, cornerRadius: Radius.card)
                }
            case .failed(let error):
                EmptyStateView.error(
                    title: ProfileStrings.personErrorTitle,
                    message: error.userMessage,
                    onRetry: onRetry
                )
            case .loaded(let person):
                // Absent values render nothing here (06 §C2); the own profile uses "—" instead.
                let candidates: [(String, String?)] = [
                    (ProfileStrings.organizationTitle, person.organizationName),
                    (ProfileStrings.personRoles, ProfileText.joined(person.roles)),
                    (ProfileStrings.phone, person.phoneNumber),
                ]
                let rows: [(String, String)] = candidates.compactMap { pair in pair.1.map { (pair.0, $0) } }
                if !rows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                            if index > 0 { RowDivider() }
                            DetailRow(label: row.0, value: row.1)
                        }
                    }
                    .background(Palette.surface, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }
            }
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
#endif
