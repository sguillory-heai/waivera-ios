#if canImport(UIKit)
    import SwiftUI
    import WaiveraAPI
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// New chat sheet: pick people, then open or create the conversation (02 §7, Android
    /// `NewChatSheet`). The app presents it in a `NavigationStack` sheet; the sheet draws its own
    /// title and close button, as Android's sheet does, and sets its own chrome.
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
                    NewChatScreen(
                        model: model,
                        avatars: avatars,
                        onOpenConversation: onOpenConversation,
                        onDismiss: onDismiss
                    )
                } else {
                    Palette.surface.ignoresSafeArea()
                }
            }
            .navigationTitle(ChatListStrings.string("chat.new.title"))
            .toolbar(.hidden, for: .navigationBar)
            .waiveraSheetPresentation()
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
        let onDismiss: () -> Void

        var body: some View {
            NewChatContentView(
                state: model.state,
                query: $model.query,
                avatar: { avatars.images[$0]?.image },
                onToggle: { model.toggle($0) },
                onSubmit: submit,
                onRetry: { Task { await model.retryLoad() } },
                onDismiss: onDismiss
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

    #if DEBUG
        #Preview("Light, demo data") {
            NavigationStack { NewChatView(onOpenConversation: { _ in }, onDismiss: {}) }
                .fakeDataEnvironment()
        }

        #Preview("Dark, failing") {
            NavigationStack { NewChatView(onOpenConversation: { _ in }, onDismiss: {}) }
                .fakeDataEnvironment(.failing)
                .preferredColorScheme(.dark)
        }

        #Preview("AX5, demo data") {
            NavigationStack { NewChatView(onOpenConversation: { _ in }, onDismiss: {}) }
                .fakeDataEnvironment()
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
