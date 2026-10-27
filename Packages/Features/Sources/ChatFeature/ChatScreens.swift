import SwiftUI
import WaiveraDesign

#if DEBUG
    import WaiveraTestSupport
#endif

/// The Chat tab root: conversation list with search and filters.
public struct ConversationListView: View {
    let onOpenConversation: (_ conversationID: Int) -> Void
    let onNewChat: () -> Void

    public init(
        onOpenConversation: @escaping (_ conversationID: Int) -> Void,
        onNewChat: @escaping () -> Void
    ) {
        self.onOpenConversation = onOpenConversation
        self.onNewChat = onNewChat
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "chat.list.title", bundle: .module),
            systemImage: "bubble.left.and.bubble.right"
        )
    }
}

/// New chat sheet: pick people, then open or create the conversation.
public struct NewChatView: View {
    let onOpenConversation: (_ conversationID: Int) -> Void
    let onDismiss: () -> Void

    public init(
        onOpenConversation: @escaping (_ conversationID: Int) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onOpenConversation = onOpenConversation
        self.onDismiss = onDismiss
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "chat.new.title", bundle: .module),
            systemImage: "square.and.pencil"
        )
    }
}

#if DEBUG
    #Preview("Light, demo data") {
        NavigationStack { ConversationListView(onOpenConversation: { _ in }, onNewChat: {}) }
            .fakeDataEnvironment()
    }
#endif
#Preview("Dark") {
    NavigationStack { ConversationListView(onOpenConversation: { _ in }, onNewChat: {}) }
        .preferredColorScheme(.dark)
}
#Preview("AX XXXL") {
    NavigationStack { NewChatView(onOpenConversation: { _ in }, onDismiss: {}) }
        .dynamicTypeSize(.accessibility5)
}
