import Foundation
import WaiveraAPI
import WaiveraData

/// Join (07 §7 "Join behaviour" and "Meeting handoff") and Message organizer.
extension CalendarEventModel {
    public func join() {
        guard case .loaded(let details) = state, let join = details.join, !join.isBusy, join.state == .open,
            let event = found?.event
        else { return }
        interaction.joinError = nil
        guard event.isSprout else {
            if let url = event.joinURL, WebLinks.isWebURL(url) {
                openRequest = OpenRequest(id: UUID(), url: url)
            } else {
                interaction.joinError = .noLink
                failureTicks += 1
            }
            rebuild()
            return
        }
        interaction.joinBusy = true
        rebuild()
        let calendar = calendar
        joinTask?.cancel()
        joinTask = Task {
            do {
                let url = try await calendar.meetingURL(for: event)
                self.lobbyReady(url)
            } catch {
                self.joinFailed(WaiveraError.from(error))
            }
        }
    }

    /// The view tried to open `openRequest`; `accepted` is false when no app took the link.
    public func linkHandled(_ request: OpenRequest, accepted: Bool) {
        guard openRequest?.id == request.id else { return }
        openRequest = nil
        if !accepted { joinFailed(nil) }
    }

    public func dismissJoinError() {
        interaction.joinError = nil
        rebuild()
    }

    /// Opens (or creates) the direct conversation with the organizer.
    public func messageOrganizer() {
        guard case .loaded(let details) = state, details.canMessageOrganizer, !interaction.chatBusy,
            let ownerId = found?.event.ownerId
        else { return }
        interaction.chatBusy = true
        interaction.chatError = nil
        rebuild()
        let conversations = conversations
        chatTask?.cancel()
        chatTask = Task {
            do {
                let conversation = try await conversations.openDirectConversation(with: ownerId)
                self.chatOpened(conversation.id)
            } catch {
                self.chatFailed(WaiveraError.from(error))
            }
        }
    }

    public func conversationHandled(_ request: ConversationRequest) {
        if conversationRequest?.id == request.id { conversationRequest = nil }
    }

    private func lobbyReady(_ url: URL) {
        interaction.joinBusy = false
        if WebLinks.isWebURL(url) {
            openRequest = OpenRequest(id: UUID(), url: url)
        } else {
            interaction.joinError = .failed(nil)
            failureTicks += 1
        }
        rebuild()
    }

    private func joinFailed(_ error: WaiveraError?) {
        interaction.joinBusy = false
        interaction.joinError = .failed(error)
        failureTicks += 1
        rebuild()
    }

    private func chatOpened(_ conversationId: Int) {
        interaction.chatBusy = false
        conversationRequest = ConversationRequest(id: UUID(), conversationId: conversationId)
        rebuild()
    }

    private func chatFailed(_ error: WaiveraError) {
        interaction.chatBusy = false
        interaction.chatError = error
        failureTicks += 1
        rebuild()
    }
}
