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

    /// A chat push is hidden in the foreground only when the hub is live and that very
    /// conversation is on screen; otherwise the user would see nothing (09 §2 fix).
    public func shouldPresentForegroundPush(conversationId: Int?) -> Bool {
        guard let conversationId, realtime.currentStatus.isConnected else { return true }
        return !presence.isActive(conversationId)
    }
}
