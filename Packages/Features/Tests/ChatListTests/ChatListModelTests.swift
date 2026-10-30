import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// The inbox model over the fake data environment: loading, empty, error, reconnect and the
/// 02 §9 acceptance checks that need no UI.
@MainActor
final class ListHarness {
    let clock: ManualClock
    let fakes: FakeDataEnvironment
    let model: ChatListModel
    private var task: Task<Void, Never>?

    init(
        _ scenario: FakeDataEnvironment.Scenario = .demo,
        conversations: (any ConversationsRepository)? = nil,
        failedSends: StateCell<Set<Int>>? = nil,
        webBaseURL: URL? = URL(string: "https://app.waivera.example")
    ) {
        let clock = ManualClock()
        let fakes = FakeDataEnvironment.make(scenario, clock: clock, webBaseURL: webBaseURL)
        self.clock = clock
        self.fakes = fakes
        model = ChatListModel(
            conversations: conversations ?? fakes.chat,
            messages: fakes.chat,
            session: fakes.session,
            realtimeStatus: fakes.realtimeStatus,
            callURL: fakes.environment.callURL,
            failedSends: Self.source(failedSends),
            text: EnglishText(),
            clock: clock,
            locale: Locale(identifier: "en_US")
        )
    }

    private static func source(_ cell: StateCell<Set<Int>>?) -> @Sendable () -> AsyncStream<Set<Int>> {
        guard let cell else { return ChatListModel.noFailedSends }
        return { cell.stream() }
    }

    func start() async {
        await fakes.environment.launch()
        task = Task { await model.start() }
    }

    func stop() {
        task?.cancel()
    }

    var ids: [Int] { model.state.rows.map(\.id) }

    func row(_ id: Int) -> ChatRow? { model.state.rows.first { $0.id == id } }
}

@MainActor
struct ChatListModelTests {
    // MARK: States

    @Test("Loading: nothing cached and the fetch in flight shows the loading content")
    func loading() async {
        let harness = ListHarness(.slow)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.fakes.chat.calls.count("refreshInbox") == 1 })
        #expect(harness.model.state.content == .loading)
        #expect(harness.model.state.rows.isEmpty)
        harness.clock.advance(by: 1)
        #expect(await eventually { harness.model.state.content == .rows })
    }

    @Test("Populated: demo rows in inbox order, newest first")
    func populated() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .rows })
        #expect(harness.ids == [63, 90, 7, 41, 58])
        let group = harness.row(63)
        #expect(group?.title == "Priya Raman & 2 others")
        #expect(group?.senderPrefix == "Jordan")
        #expect(group?.timeLabel == "20m")
        #expect(group?.unreadCount == 2)
        #expect(harness.row(90)?.leading == .bot)
        #expect(harness.row(41)?.leading == .channel(archived: false))
        #expect(harness.row(41)?.hasAttachment == true)
        #expect(harness.row(58)?.isReadOnly == true)
        #expect(harness.row(58)?.preview == "No messages yet")
        #expect(harness.row(7)?.senderPrefix == "You")
    }

    @Test("Empty: a loaded inbox with nothing in it says No conversations yet")
    func empty() async {
        let harness = ListHarness(.empty)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .empty(.noConversations) })
    }

    @Test("Error: nothing cached and the fetch failed shows the typed error; Retry recovers")
    func errorThenRetry() async {
        let harness = ListHarness(.failing)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .error(.server(statusCode: 503)) })
        harness.fakes.chat.setInboxControls(FakeControls())
        await harness.model.refresh()
        #expect(await eventually { harness.model.state.content == .rows })
        #expect(harness.model.state.refreshError == nil)
    }

    @Test("A failed refresh keeps the cached rows and raises the refresh banner")
    func refreshFailureKeepsRows() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .rows })
        harness.fakes.chat.setInboxControls(FakeControls(failure: .offline))
        await harness.model.refresh()
        #expect(await eventually { harness.model.state.refreshError == .offline })
        #expect(harness.model.state.rows.count == 5)
    }

    @Test("Reconnect: the pill follows the hub through reconnecting and back to online")
    func reconnect() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .rows })
        #expect(await eventually { harness.model.state.connection == .online })
        harness.fakes.realtime.drop(attempt: 2)
        #expect(await eventually { harness.model.state.connection == .reconnecting })
        #expect(harness.model.state.rows.count == 5)
        await harness.model.retryConnection()
        #expect(await eventually { harness.model.state.connection == .online })
        #expect(harness.fakes.realtime.log.retries == 1)
        harness.fakes.realtimeStatus.setOffline(true)
        #expect(await eventually { harness.model.state.connection == .offline })
    }

    @Test("Connection mapping: offline device wins; a hub that never connected is Connecting")
    func connectionMapping() {
        #expect(ChatListModel.connection(banner: .offline, isConnected: true, epoch: 3) == .offline)
        #expect(
            ChatListModel.connection(banner: .reconnecting(attempt: 1), isConnected: false, epoch: 1) == .reconnecting
        )
        #expect(ChatListModel.connection(banner: .connecting, isConnected: false, epoch: 0) == .connecting)
        #expect(ChatListModel.connection(banner: .hidden, isConnected: true, epoch: 1) == .online)
        #expect(ChatListModel.connection(banner: .hidden, isConnected: false, epoch: 0) == .connecting)
        #expect(ChatListModel.connection(banner: .hidden, isConnected: false, epoch: 2) == .offline)
    }

    @Test("Cold start: a cached inbox renders before the network answers")
    func coldStartFromCache() async {
        let clock = ManualClock()
        let cached = Sample.conversation(
            #"{"id": 7, "participants": [\#(Sample.me), \#(Sample.priya)], "lastMessage": {"id": 1, "#
                + #""userId": "usr_priya_raman", "messagePlaintext": "cached", "createDate": "2026-11-01T14:00:00Z"}}"#
        )
        let stub = StubConversations([cached], updatedAt: nil, phase: .loading, clock: clock)
        let harness = ListHarness(conversations: stub)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.model.state.content == .rows })
        #expect(harness.row(7)?.preview == "cached")
    }

    // MARK: Ordering and realtime

    @Test("A realtime message for an older conversation moves it to the top at once")
    func realtimeMovesToTop() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.first == 63 })
        await harness.fakes.chat.receive(Sample.message(id: 20_001, conversationId: 41, text: "new roster"))
        #expect(await eventually { harness.ids.first == 41 })
        #expect(harness.row(41)?.preview == "new roster")
        #expect(harness.row(41)?.unreadCount == 4)
        #expect(harness.row(41)?.arrivalKey == 20_001)
        // The arrival's timer starts in its own task, which may not be asleep on the manual clock
        // yet under a loaded parallel run; keep moving time until it has fired.
        #expect(
            await eventually {
                harness.clock.advance(by: 2)
                return harness.row(41)?.arrivalKey == nil
            }
        )
    }

    @Test("Scrolled down, rows hold their place and the pill offers the new order")
    func scrolledDownHoldsOrder() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids == [63, 90, 7, 41, 58] })
        harness.model.setAtTop(false)
        await harness.fakes.chat.receive(Sample.message(id: 20_002, conversationId: 41, text: "while away"))
        #expect(await eventually { harness.row(41)?.preview == "while away" })
        #expect(harness.ids == [63, 90, 7, 41, 58])
        #expect(harness.model.state.hasPendingReorder)
        harness.model.showNewActivity()
        #expect(harness.ids.first == 41)
        #expect(!harness.model.state.hasPendingReorder)
    }

    @Test("Returning to the top applies the waiting order")
    func backToTopApplies() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.model.setAtTop(false)
        await harness.fakes.chat.receive(Sample.message(id: 20_003, conversationId: 7, text: "hi"))
        #expect(await eventually { harness.model.state.hasPendingReorder })
        harness.model.setAtTop(true)
        #expect(harness.ids.first == 7)
    }

    @Test("My own message does not play the arrival wash")
    func ownMessageNoArrival() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        await harness.fakes.chat.receive(
            Sample.message(id: 20_004, conversationId: 41, authorId: Sample.viewer, text: "mine")
        )
        #expect(await eventually { harness.row(41)?.preview == "mine" })
        #expect(harness.row(41)?.arrivalKey == nil)
        #expect(harness.row(41)?.senderPrefix == "You")
    }

    @Test("Relative labels tick on the shared 30-second clock")
    func labelsTick() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.row(63)?.timeLabel == "20m" })
        #expect(await eventually { harness.clock.pendingSleepers > 0 })
        harness.clock.advance(by: 30)
        #expect(await eventually { harness.clock.pendingSleepers > 0 && harness.row(63)?.timeLabel == "20m" })
        harness.clock.advance(by: 30)
        #expect(await eventually { harness.row(63)?.timeLabel == "21m" })
    }

    // MARK: Typing and calls

    @Test("Typing replaces the preview and reverts when it stops")
    func typingOverride() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.fakes.chat.setTyping(["usr_priya_raman"], in: 63)
        #expect(await eventually { harness.row(63)?.typingLabel == "Priya Raman is typing…" })
        #expect(harness.row(63)?.accessibilityText.contains("Priya Raman is typing…") == true)
        harness.fakes.chat.setTyping(["usr_priya_raman", "usr_jordan_lee"], in: 63)
        #expect(await eventually { harness.row(63)?.typingLabel == "Several people are typing…" })
        harness.fakes.chat.setTyping([], in: 63)
        #expect(await eventually { harness.row(63)?.typingLabel == nil })
    }

    @Test("A live call shows the join row; joining returns an https lobby without navigating")
    func liveCall() async {
        let clock = ManualClock()
        var calling = Sample.conversation(#"{"id": 7, "participants": [\#(Sample.me), \#(Sample.priya)]}"#)
        calling.activeCall = CallRoom(roomId: "room-1")
        let stub = StubConversations([calling], updatedAt: clock.now, clock: clock)
        let harness = ListHarness(conversations: stub)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.row(7)?.isCallLive == true })
        #expect(harness.row(7)?.accessibilityText.contains("Call in progress · Join") == true)
        let url = await harness.model.joinCall(conversationId: 7)
        #expect(url?.scheme == "https")
        #expect(harness.row(7)?.isOpeningCall == false)
        // Joining is its own action: the row's navigation lock is untouched.
        #expect(harness.model.open(conversationId: 7))
    }

    @Test("A call that cannot open posts a notice with Retry")
    func callFailure() async {
        let clock = ManualClock()
        var calling = Sample.conversation(#"{"id": 7, "participants": [\#(Sample.me), \#(Sample.priya)]}"#)
        calling.activeCall = CallRoom(roomId: "room-1")
        let stub = StubConversations([calling], updatedAt: clock.now, clock: clock)
        let harness = ListHarness(conversations: stub, webBaseURL: nil)
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.row(7)?.isCallLive == true })
        let url = await harness.model.joinCall(conversationId: 7)
        #expect(url == nil)
        #expect(harness.model.state.notice?.kind == .callFailed(conversationId: 7))
        harness.model.dismissNotice()
        #expect(harness.model.state.notice == nil)
    }

}

extension ChatListModelTests {
    // MARK: Filters, search, navigation

    @Test("The Unread filter says You're all caught up once the last unread is read")
    func unreadFilterCaughtUp() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.model.filter = .unread
        #expect(harness.ids == [63, 90, 7, 41])
        for id in [63, 90, 7, 41] { try? await harness.fakes.chat.markRead(conversationId: id) }
        #expect(await eventually { harness.model.state.content == .empty(.allCaughtUp) })
    }

    @Test("The Channels filter keeps channels only")
    func channelsFilter() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.model.filter = .channels
        #expect(harness.ids == [41, 58])
    }

    @Test("A query that matches no title or preview says No conversations match your search")
    func searchNoMatch() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.model.query = "van 2"
        #expect(harness.ids == [63])
        harness.model.query = "zzz"
        #expect(harness.model.state.content == .empty(.noMatches))
    }

    @Test("A double tap navigates once; the lock clears when the list appears again")
    func doubleTap() async {
        let harness = ListHarness()
        #expect(harness.model.open(conversationId: 7))
        #expect(!harness.model.open(conversationId: 7))
        #expect(!harness.model.open(conversationId: 41))
        harness.model.appeared()
        #expect(harness.model.open(conversationId: 41))
    }

    // MARK: Staleness

    @Test("Returning within 60 seconds does not refetch; after 60 seconds it does")
    func staleness() async {
        let harness = ListHarness()
        await harness.start()
        #expect(await eventually { harness.ids.count == 5 })
        #expect(harness.fakes.chat.calls.count("refreshInbox") == 1)
        harness.stop()
        harness.clock.advance(by: 30)
        await harness.start()
        await settle()
        #expect(harness.fakes.chat.calls.count("refreshInbox") == 1)
        harness.stop()
        harness.clock.advance(by: 31)
        await harness.start()
        #expect(await eventually { harness.fakes.chat.calls.count("refreshInbox") == 2 })
        harness.stop()
    }

    @Test("The first 30 rows' peers are prefetched, without bots, groups or channels")
    func avatarIds() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        #expect(harness.model.avatarUserIds == ["usr_priya_raman"])
    }
}
