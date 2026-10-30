import Foundation
import WaiveraAPI
import WaiveraData

/// The streams the inbox follows: conversations, typing, failed sends, the session, the hub
/// and the clock.
extension ChatListModel {
    func observeConversations() async {
        for await next in conversations.conversations() {
            apply(next)
            if !checkedStaleness, next.phase != .loading {
                checkedStaleness = true
                if isStale(next) { Task { await self.refreshInBackground() } }
            }
        }
    }

    func observeTyping() async {
        for await next in conversations.typing() {
            typing = next
            rebuild()
        }
    }

    func observeFailedSends() async {
        for await next in failedSendsSource() {
            failedSends = next
            rebuild()
        }
    }

    func observeSession() async {
        for await next in session.states() {
            user = next.user
            rebuild()
        }
    }

    func observeBanner() async {
        for await next in realtimeStatus.banner() {
            banner = next
            updateConnection()
        }
    }

    func observeStatuses() async {
        for await status in realtimeStatus.statuses() {
            isHubConnected = status.isConnected
            hubEpoch = status.epoch
            updateConnection()
        }
    }

    func tick() async {
        while !Task.isCancelled {
            do {
                try await clock.sleep(for: RelativeTimeFormatter.tickInterval)
            } catch {
                return
            }
            now = clock.now
            rebuild()
        }
    }

    func refreshInBackground() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await conversations.refresh()
        isRefreshing = false
    }

    private func isStale(_ resource: Resource<[Conversation]>) -> Bool {
        guard let updatedAt = resource.updatedAt else { return true }
        return clock.now.timeIntervalSince(updatedAt) >= Self.staleAfter
    }
}
