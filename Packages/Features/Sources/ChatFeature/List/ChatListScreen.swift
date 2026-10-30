#if canImport(UIKit)
    import SwiftUI
    import UIKit
    import WaiveraData
    import WaiveraDesign

    #if DEBUG
        import WaiveraTestSupport
    #endif

    /// The Chat tab root (Android `ChatListRoute`): the hero bar with "+" and the account avatar,
    /// then the inbox with search and filters (02). The hero replaces the navigation bar, which
    /// stays hidden; its title still names the back button on pushed screens.
    public struct ConversationListView: View {
        let onOpenConversation: (_ conversationID: Int) -> Void
        let onOpenPerson: (_ userID: String) -> Void
        let onNewChat: () -> Void
        let accountName: String?
        let accountLabel: String?
        let onAccount: (() -> Void)?

        @Environment(\.dataEnvironment) private var data
        @State private var model: ChatListModel?
        @State private var avatars: AvatarPrefetcher<AvatarImage>?

        /// - Parameters:
        ///   - accountName: the signed-in person, whose avatar on the hero bar opens `onAccount`
        ///     (the account menu). Without both, the bar shows no avatar.
        public init(
            onOpenConversation: @escaping (_ conversationID: Int) -> Void,
            onOpenPerson: @escaping (_ userID: String) -> Void,
            onNewChat: @escaping () -> Void,
            accountName: String? = nil,
            accountLabel: String? = nil,
            onAccount: (() -> Void)? = nil
        ) {
            self.onOpenConversation = onOpenConversation
            self.onOpenPerson = onOpenPerson
            self.onNewChat = onNewChat
            self.accountName = accountName
            self.accountLabel = accountLabel
            self.onAccount = onAccount
        }

        public var body: some View {
            Group {
                if let model, let avatars {
                    ChatListScreen(
                        model: model,
                        avatars: avatars,
                        account: account,
                        onOpenConversation: onOpenConversation,
                        onOpenPerson: onOpenPerson,
                        onNewChat: onNewChat
                    )
                } else {
                    // Only before the first frame's task runs, or in an unconfigured build.
                    Palette.background.ignoresSafeArea()
                }
            }
            .navigationTitle(ChatListStrings.string("chat.list.title"))
            .toolbar(.hidden, for: .navigationBar)
            .task {
                guard model == nil, let data else { return }
                model = ChatListModel(environment: data)
                avatars = AvatarPrefetcher(repository: data.avatars) { AvatarImage(data: $0) }
            }
        }

        private var account: ChatListAccount? {
            guard let accountName, let onAccount else { return nil }
            return ChatListAccount(name: accountName, accessibilityLabel: accountLabel, onOpen: onAccount)
        }
    }

    /// Binds the model to the stateless content and turns its answers into navigation.
    struct ChatListScreen: View {
        @Bindable var model: ChatListModel
        let avatars: AvatarPrefetcher<AvatarImage>
        let account: ChatListAccount?
        let onOpenConversation: (Int) -> Void
        let onOpenPerson: (String) -> Void
        let onNewChat: () -> Void

        @Environment(\.openURL) private var openURL

        var body: some View {
            ChatListContentView(
                state: model.state,
                query: $model.query,
                filter: $model.filter,
                avatar: { avatars.images[$0]?.image },
                account: account,
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
                onViewProfile: onOpenPerson,
                onRefresh: { [model] in await model.refresh() },
                onRetryLoad: { Task { await model.refresh() } },
                onTopVisibilityChange: { model.setAtTop($0) },
                onShowNewActivity: { model.showNewActivity() },
                onDismissNotice: { model.dismissNotice() },
                onRetryNotice: { notice in
                    switch notice.kind {
                    case .callFailed(let conversationId): joinCall(conversationId)
                    case .markReadFailed(let conversationId): model.markRead(conversationId: conversationId)
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
        @MainActor private var previewList: some View {
            ConversationListView(
                onOpenConversation: { _ in },
                onOpenPerson: { _ in },
                onNewChat: {},
                accountName: "Alex Rivera",
                onAccount: {}
            )
        }

        #Preview("Light, demo data") {
            NavigationStack { previewList }
                .fakeDataEnvironment()
        }

        #Preview("Dark, empty") {
            NavigationStack { previewList }
                .fakeDataEnvironment(.empty)
                .preferredColorScheme(.dark)
        }

        #Preview("AX5, failing") {
            NavigationStack { previewList }
                .fakeDataEnvironment(.failing)
                .dynamicTypeSize(.accessibility5)
        }
    #endif
#endif
