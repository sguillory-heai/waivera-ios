import Foundation
import WaiveraRealtime

public final class LiveChatAlertsRepository: ChatAlertsRepository {
    private let chat: ChatEngine
    private let presence: ChatPresence
    private let realtime: any RealtimeClient

    public init(chat: ChatEngine, presence: ChatPresence, realtime: any RealtimeClient) {
        self.chat = chat
        self.presence = presence
        self.realtime = realtime
    }

    public func alerts() -> AsyncStream<ChatAlert> { chat.alerts() }

    public func conversationsRead() -> AsyncStream<Int> { chat.conversationsRead() }

    /// A chat push is hidden in the foreground only when the hub is live and the surface the
    /// message belongs to is on screen: the conversation's timeline for a root message, the
    /// thread for a reply. Otherwise the user would see nothing (09 §2 fix, IF-02).
    public func shouldPresentForegroundPush(conversationId: Int?, threadRootMessageId: Int?) -> Bool {
        guard let conversationId, realtime.currentStatus.isConnected else { return true }
        return !presence.isActive(conversationId: conversationId, threadRootMessageId: threadRootMessageId)
    }
}
