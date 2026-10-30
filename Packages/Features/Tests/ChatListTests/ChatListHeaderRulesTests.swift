import Testing
import WaiveraAPI

@testable import ChatFeature

/// One connection signal at a time (Android `ChatListHeaderRulesTest`): the shell's banner owns
/// offline and reconnecting, so the header shows only the slow start-up pill and the refresh banner.
struct ChatListHeaderRulesTests {
    private let rows = ChatListState(content: .rows, connection: .online)

    private func with(_ connection: ConnectionIndicator, refreshError: WaiveraError? = nil) -> ChatListState {
        var state = rows
        state.connection = connection
        state.refreshError = refreshError
        return state
    }

    @Test("Online never shows a pill; connecting does when nothing else is up")
    func connectingPill() {
        #expect(!ChatListHeaderRules.showsConnectingPill(with(.online)))
        #expect(ChatListHeaderRules.showsConnectingPill(with(.connecting)))
        #expect(!ChatListHeaderRules.showsConnectingPill(with(.offline)))
        #expect(!ChatListHeaderRules.showsConnectingPill(with(.reconnecting)))
        #expect(!ChatListHeaderRules.showsConnectingPill(with(.connecting, refreshError: .server(statusCode: 500))))
        let error = ChatListState(content: .error(.offline), connection: .connecting)
        #expect(!ChatListHeaderRules.showsConnectingPill(error))
    }

    @Test("The refresh banner shows while connected and folds into the shell's banner while down")
    func refreshBanner() {
        #expect(!ChatListHeaderRules.showsRefreshBanner(with(.online)))
        #expect(ChatListHeaderRules.showsRefreshBanner(with(.online, refreshError: .server(statusCode: 500))))
        #expect(ChatListHeaderRules.showsRefreshBanner(with(.connecting, refreshError: .offline)))
        #expect(!ChatListHeaderRules.showsRefreshBanner(with(.offline, refreshError: .offline)))
        #expect(!ChatListHeaderRules.showsRefreshBanner(with(.reconnecting, refreshError: .offline)))
    }

    @Test("Rows share one card, rounded at its first and last row only")
    func cardPositions() {
        #expect(InboxCardPosition.of(index: 0, count: 1) == .single)
        #expect(InboxCardPosition.of(index: 0, count: 3) == .first)
        #expect(InboxCardPosition.of(index: 1, count: 3) == .middle)
        #expect(InboxCardPosition.of(index: 2, count: 3) == .last)
        #expect(InboxCardPosition.single.isLast)
        #expect(!InboxCardPosition.first.isLast)
        #expect(InboxCardPosition.first.roundsTop && !InboxCardPosition.first.roundsBottom)
        #expect(!InboxCardPosition.middle.roundsTop && !InboxCardPosition.middle.roundsBottom)
    }
}
