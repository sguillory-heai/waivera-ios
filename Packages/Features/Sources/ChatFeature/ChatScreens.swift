import SwiftUI
import WaiveraDesign

#if DEBUG
    import WaiveraTestSupport
#endif

/// One conversation. Scrolls to and highlights `targetMessageID` when given.
public struct ConversationView: View {
    let conversationID: Int
    let targetMessageID: Int?
    let onOpenThread: (_ rootMessageID: Int, _ targetMessageID: Int?) -> Void
    let onOpenPerson: (_ userID: String) -> Void

    public init(
        conversationID: Int,
        targetMessageID: Int?,
        onOpenThread: @escaping (_ rootMessageID: Int, _ targetMessageID: Int?) -> Void,
        onOpenPerson: @escaping (_ userID: String) -> Void
    ) {
        self.conversationID = conversationID
        self.targetMessageID = targetMessageID
        self.onOpenThread = onOpenThread
        self.onOpenPerson = onOpenPerson
/// The Chat tab root: conversation list with search and filters.
public struct ConversationListView: View {
    let onOpenConversation: (_ conversationID: Int) -> Void
    let onNewChat: () -> Void
        onOpenConversation: @escaping (_ conversationID: Int) -> Void,
        onNewChat: @escaping () -> Void
        self.onOpenConversation = onOpenConversation
        self.onNewChat = onNewChat
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "chat.conversation.title", bundle: .module),
            systemImage: "bubble.left",
            details: ["conversationId \(conversationID)"]
                + [targetMessageID.map { "messageId \($0)" }].compactMap { $0 }
            title: String(localized: "chat.list.title", bundle: .module),
            systemImage: "bubble.left.and.bubble.right"
        )
    }
}

/// A thread under its root message. Joins the conversation's hub group.
public struct ThreadView: View {
    let rootMessageID: Int
    let conversationID: Int?
    let targetMessageID: Int?
    let onOpenPerson: (_ userID: String) -> Void

    public init(
        rootMessageID: Int,
        conversationID: Int?,
        targetMessageID: Int?,
        onOpenPerson: @escaping (_ userID: String) -> Void
    ) {
        self.rootMessageID = rootMessageID
        self.conversationID = conversationID
        self.targetMessageID = targetMessageID
        self.onOpenPerson = onOpenPerson
/// New chat sheet: pick people, then open or create the conversation.
public struct NewChatView: View {
    let onOpenConversation: (_ conversationID: Int) -> Void
    let onDismiss: () -> Void
        onOpenConversation: @escaping (_ conversationID: Int) -> Void,
        onDismiss: @escaping () -> Void
        self.onOpenConversation = onOpenConversation
        self.onDismiss = onDismiss
    }

    public var body: some View {
        FeaturePlaceholder(
            title: String(localized: "chat.thread.title", bundle: .module),
            systemImage: "arrowshape.turn.up.left.2",
            details: ["rootMessageId \(rootMessageID)"]
                + [conversationID.map { "conversationId \($0)" }].compactMap { $0 }
                + [targetMessageID.map { "messageId \($0)" }].compactMap { $0 }
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
