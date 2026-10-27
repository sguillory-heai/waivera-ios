#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// New chat sheet: pick people, then open or create the conversation (02 §7). The app
    /// presents it in a `NavigationStack` sheet; it sets its own detents.
    public struct NewChatView: View {
        let onOpenConversation: (_ conversationID: Int) -> Void
        let onDismiss: () -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: NewChatModel?
        @State private var avatars: AvatarPrefetcher<AvatarImage>?

        public init(
            onOpenConversation: @escaping (_ conversationID: Int) -> Void,
            onDismiss: @escaping () -> Void
        ) {
            self.onOpenConversation = onOpenConversation
            self.onDismiss = onDismiss
        }

        public var body: some View {
            Group {
                if let model, let avatars {
                    NewChatScreen(model: model, avatars: avatars, onOpenConversation: onOpenConversation)
                } else {
                    Palette.background.ignoresSafeArea()
                }
            }
            .navigationTitle(ChatListStrings.string("chat.new.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(ChatListStrings.string("chat.new.close"), action: onDismiss)
                        .foregroundStyle(Palette.accent)
                        .accessibilityIdentifier("newChat.close")
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .task {
                guard model == nil, let data else { return }
                model = NewChatModel(environment: data)
                avatars = AvatarPrefetcher(repository: data.avatars) { AvatarImage(data: $0) }
            }
        }
    }

    struct NewChatScreen: View {
        @Bindable var model: NewChatModel
        let avatars: AvatarPrefetcher<AvatarImage>
        let onOpenConversation: (Int) -> Void

        var body: some View {
            NewChatContentView(
                state: model.state,
                query: $model.query,
                avatar: { avatars.images[$0]?.image },
                onToggle: { model.toggle($0) },
                onSubmit: submit,
                onRetry: { Task { await model.retryLoad() } }
            )
            .task { await model.start() }
            .task(id: visibleIds) { await avatars.prefetch(visibleIds) }
            .onDisappear { model.reset() }
        }

        private var visibleIds: [String] {
            model.state.people.prefix(ChatListModel.avatarRows).map(\.id)
        }

        private func submit() {
            Task {
                if let conversationId = await model.submit() { onOpenConversation(conversationId) }
            }
        }
    }

    /// The picker, stateless apart from presentation timing.
    struct NewChatContentView: View {
        let state: NewChatState
        @Binding var query: String
        let avatar: (String) -> Image?
        let onToggle: (String) -> Void
        let onSubmit: () -> Void
        let onRetry: () -> Void

        @State private var isSkeletonVisible: Bool

        /// `showsSkeletonImmediately` skips the ~300 ms delay, for snapshot tests only.
        init(
            state: NewChatState,
            query: Binding<String>,
            avatar: @escaping (String) -> Image? = { _ in nil },
            onToggle: @escaping (String) -> Void = { _ in },
            onSubmit: @escaping () -> Void = {},
            onRetry: @escaping () -> Void = {},
            showsSkeletonImmediately: Bool = false
        ) {
            self.state = state
            _query = query
            self.avatar = avatar
            self.onToggle = onToggle
            self.onSubmit = onSubmit
            self.onRetry = onRetry
            _isSkeletonVisible = State(initialValue: showsSkeletonImmediately)
        }

        var body: some View {
            List {
                Section {
                    Text(ChatListStrings.string("chat.new.subtitle"))
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.textSecondary)
                        .listRowSeparator(.hidden)
                        .listRowBackground(Palette.background)
                    if state.selectedCount > 0 {
                        Text(ChatListStrings.format("chat.new.selected", state.selectedCount))
                            .font(WaiveraFont.captionEmphasis)
                            .foregroundStyle(Palette.accent)
                            .listRowSeparator(.hidden)
                            .listRowBackground(Palette.background)
                    }
                }
                content
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(Palette.background)
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: Text(ChatListStrings.string("chat.new.search.prompt"))
            )
            .autocorrectionDisabled()
            .safeAreaInset(edge: .bottom) { footer }
            .skeletonGate(isLoading: state.content == .loading, isVisible: $isSkeletonVisible)
            .waiveraHaptic(.selection, trigger: state.selectedCount)
            .waiveraHaptic(.failure, trigger: state.error) { _, new in new != nil }
        }

        @ViewBuilder private var content: some View {
            switch state.content {
            case .loading:
                if isSkeletonVisible {
                    SkeletonList(rows: 6)
                        .listRowInsets(EdgeInsets())
                        .listRowSeparator(.hidden)
                        .listRowBackground(Palette.background)
                }
            case .error(let error):
                EmptyStateView.error(
                    title: ChatListStrings.string("chat.new.error.title"),
                    message: error.userMessage,
                    onRetry: onRetry
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Palette.background)
            case .empty:
                EmptyStateView(
                    systemImage: "person.2.fill",
                    title: ChatListStrings.string("chat.new.empty.title"),
                    message: ChatListStrings.string("chat.new.empty")
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Palette.background)
            case .people:
                ForEach(state.people) { person in
                    PersonPickerRow(person: person, avatar: avatar(person.id)) { onToggle(person.id) }
                        .listRowSeparatorTint(Palette.border)
                        .listRowBackground(person.isSelected ? Palette.accentWash : Palette.background)
                        .disabled(state.isCreating)
                }
            }
        }

        private var footer: some View {
            VStack(spacing: Spacing.small) {
                if let error = state.error {
                    Text(error.userMessage)
                        .font(WaiveraFont.caption)
                        .foregroundStyle(Palette.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("newChat.error")
                }
                WaiveraButton(
                    ChatListStrings.string(state.action == .openChat ? "chat.new.open" : "chat.new.createGroup"),
                    isLoading: state.isCreating,
                    action: onSubmit
                )
                .disabled(!state.canSubmit)
                .accessibilityIdentifier("newChat.submit")
            }
            .padding(Spacing.medium)
            .background(Palette.background)
        }
    }

    /// Avatar, name and a check that fills when selected. The selected state is spoken.
    private struct PersonPickerRow: View {
        let person: PersonOption
        let avatar: Image?
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: Spacing.smallPlus) {
                    AvatarView(name: person.name, image: avatar)
                        .accessibilityHidden(true)
                    Text(person.name)
                        .font(WaiveraFont.bodyEmphasis)
                        .foregroundStyle(Palette.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: person.isSelected ? "checkmark.circle.fill" : "circle")
                        .font(WaiveraFont.sectionTitle)
                        .foregroundStyle(person.isSelected ? Palette.accent : Palette.textSecondary)
                        .accessibilityHidden(true)
                }
                .padding(.vertical, Spacing.extraSmall)
                .frame(minHeight: ControlSize.minHitTarget)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .waiveraAnimation(.state, value: person.isSelected)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(person.name))
            .accessibilityAddTraits(person.isSelected ? [.isButton, .isSelected] : .isButton)
            .accessibilityIdentifier("newChat.person.\(person.id)")
        }
    }

    #if DEBUG
        private struct PickerPreview: View {
            let state: NewChatState
            @State private var query = ""

            var body: some View {
                NavigationStack {
                    NewChatContentView(state: state, query: $query)
                        .navigationTitle(ChatListStrings.string("chat.new.title"))
                        .navigationBarTitleDisplayMode(.inline)
                }
            }
        }

        private let samplePeople = [
            PersonOption(id: "usr_jordan_lee", name: "Jordan Lee", isSelected: true),
            PersonOption(id: "usr_priya_raman", name: "Priya Raman", isSelected: false),
            PersonOption(id: "usr_sam_ortiz", name: "Sam Ortiz", isSelected: true),
        ]

        #Preview("Light, demo data") {
            NavigationStack { NewChatView(onOpenConversation: { _ in }, onDismiss: {}) }
                .fakeDataEnvironment()
        }

        #Preview("Dark, two selected") {
            PickerPreview(state: NewChatState(content: .people, people: samplePeople, selectedCount: 2))
                .preferredColorScheme(.dark)
        }

        #Preview("AX XXXL, error") {
            PickerPreview(
                state: NewChatState(content: .people, people: samplePeople, selectedCount: 2, error: .offline)
            )
            .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
