#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Chat tab root: conversation list with search and filters (02).
    public struct ConversationListView: View {
        let onOpenConversation: (_ conversationID: Int) -> Void
        let onNewChat: () -> Void

        @Environment(\.dataEnvironment) private var data
        @State private var model: ChatListModel?
        @State private var avatars: AvatarPrefetcher<AvatarImage>?

        public init(
            onOpenConversation: @escaping (_ conversationID: Int) -> Void,
            onNewChat: @escaping () -> Void
        ) {
            self.onOpenConversation = onOpenConversation
            self.onNewChat = onNewChat
        }

        public var body: some View {
            Group {
                if let model, let avatars {
                    ChatListScreen(
                        model: model,
                        avatars: avatars,
                        onOpenConversation: onOpenConversation,
                        onNewChat: onNewChat
                    )
                } else {
                    // Only before the first frame's task runs, or in an unconfigured build.
                    Palette.background.ignoresSafeArea()
                }
            }
            .navigationTitle(ChatListStrings.string("chat.list.title"))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: onNewChat) {
                        Image(systemName: "square.and.pencil")
                            .foregroundStyle(Palette.accent)
                            .frame(width: ControlSize.minHitTarget, height: ControlSize.minHitTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(Text(ChatListStrings.string("chat.list.newChat")))
                    .accessibilityIdentifier("chatList.newChat")
                }
            }
            .task {
                guard model == nil, let data else { return }
                model = ChatListModel(environment: data)
                avatars = AvatarPrefetcher(repository: data.avatars) { AvatarImage(data: $0) }
            }
        }
    }

    /// Binds the model to the stateless content and turns its answers into navigation.
    struct ChatListScreen: View {
        @Bindable var model: ChatListModel
        let avatars: AvatarPrefetcher<AvatarImage>
        let onOpenConversation: (Int) -> Void
        let onNewChat: () -> Void

        @Environment(\.openURL) private var openURL

        var body: some View {
            ChatListContentView(
                state: model.state,
                query: $model.query,
                filter: $model.filter,
                avatar: { avatars.images[$0]?.image },
                actions: actions
            )
            .task { await model.start() }
            .task(id: model.avatarUserIds) { await avatars.prefetch(model.avatarUserIds) }
            .onAppear { model.appeared() }
        }

        private var actions: ChatListActions {
            ChatListActions(
                onOpen: open,
                onNewChat: onNewChat,
                onMarkRead: { model.markRead(conversationId: $0) },
                onJoinCall: joinCall,
                onViewProfile: viewProfile,
                onRefresh: { [model] in await model.refresh() },
                onRetryLoad: { Task { await model.refresh() } },
                onTopVisibilityChange: { model.setAtTop($0) },
                onShowNewActivity: { model.showNewActivity() },
                onDismissNotice: { model.dismissNotice() },
                onRetryNotice: { notice in
                    switch notice.kind {
                    case .callFailed(let conversationId): joinCall(conversationId)
                    }
                }
            )
        }

        private func open(_ conversationId: Int) {
            if model.open(conversationId: conversationId) { onOpenConversation(conversationId) }
        }

        /// The lobby opens in the browser; there is no native calling (03 §19).
        private func joinCall(_ conversationId: Int) {
            Task {
                guard let url = await model.joinCall(conversationId: conversationId) else { return }
                openURL(url)
            }
        }

        /// Through the app's own `waivera://people/{id}` link: the entry view has no person
        /// closure (docs/requests/chat-list.md asks for one).
        private func viewProfile(_ userId: String) {
            guard let encoded = userId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
                let url = URL(string: "waivera://people/\(encoded)")
            else { return }
            openURL(url)
        }
    }

    /// A decoded avatar. `UIImage` is immutable once created, so sharing it across the decode
    /// task and the main actor is safe.
    struct AvatarImage: @unchecked Sendable {
        let uiImage: UIImage

        init?(data: Data) {
            guard let image = UIImage(data: data) else { return nil }
            uiImage = image
        }

        var image: Image { Image(uiImage: uiImage) }
    }

    #if DEBUG
        #Preview("Light, demo data") {
            NavigationStack { ConversationListView(onOpenConversation: { _ in }, onNewChat: {}) }
                .fakeDataEnvironment()
        }

        #Preview("Dark, empty") {
            NavigationStack { ConversationListView(onOpenConversation: { _ in }, onNewChat: {}) }
                .fakeDataEnvironment(.empty)
                .preferredColorScheme(.dark)
        }

        #Preview("AX XXXL, failing") {
            NavigationStack { ConversationListView(onOpenConversation: { _ in }, onNewChat: {}) }
                .fakeDataEnvironment(.failing)
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
