import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Realtime status and alerts")
struct StatusAndAlertTests {
    @Test func bannerMapping() {
        typealias Repo = LiveRealtimeStatusRepository
        #expect(Repo.banner(status: RealtimeStatus(state: .connected, epoch: 3), online: true) == .hidden)
        #expect(Repo.banner(status: RealtimeStatus(state: .connecting, epoch: 0), online: true) == .connecting)
        #expect(
            Repo.banner(status: RealtimeStatus(state: .connecting, epoch: 2), online: true) == .reconnecting(attempt: 1)
        )
        #expect(
            Repo.banner(
                status: RealtimeStatus(state: .reconnecting(attempt: 9, delay: .seconds(30)), epoch: 2),
                online: true
            )
                == .reconnecting(attempt: 9)
        )
        #expect(Repo.banner(status: RealtimeStatus(state: .connected, epoch: 3), online: false) == .offline)
    }

    @Test func bannerFollowsConnectivity() async {
        let realtime = FakeRealtime()
        let connectivity = ManualConnectivity(online: true)
        let repository = LiveRealtimeStatusRepository(realtime: realtime, connectivity: connectivity)
        connectivity.set(online: false)
        #expect(await eventually { await latest(repository.banner()) == .offline })
        connectivity.set(online: true)
        realtime.connect()
        #expect(await eventually { await latest(repository.banner()) == .hidden })
    }

    @Test func foregroundPushIsSuppressedOnlyWhenConnectedAndOnScreen() async {
        let harness = ChatHarness()
        let alerts = LiveChatAlertsRepository(
            chat: harness.engine,
            presence: harness.presence,
            realtime: harness.realtime
        )
        harness.presence.setVisible(7, true)
        #expect(alerts.shouldPresentForegroundPush(conversationId: 7))
        harness.realtime.connect()
        #expect(!alerts.shouldPresentForegroundPush(conversationId: 7))
        #expect(alerts.shouldPresentForegroundPush(conversationId: 41))
        #expect(alerts.shouldPresentForegroundPush(conversationId: nil))
        harness.presence.setForeground(false)
        #expect(alerts.shouldPresentForegroundPush(conversationId: 7))
    }

    @Test func attentionBecomesAnAlertOutsideTheOpenConversation() async throws {
        let harness = ChatHarness()
        await harness.begin()
        let received = LockedValue<[ChatAlert]>([])
        let stream = harness.engine.alerts()
        let collector = Task {
            for await alert in stream { received.update { $0.append(alert) } }
        }
        defer { collector.cancel() }
        await settle()
        // The fixture is the viewer's own mention of someone else: never an alert for them.
        await harness.engine.handle(try hubEvent("hub-receive-chat-attention"))
        await harness.engine.handle(.attention(message(9500, in: 7, text: "@Alex can you?"), reason: .mention))
        harness.presence.setVisible(41, true)
        await harness.engine.handle(.attention(message(9501, in: 41, text: "on screen"), reason: .message))
        #expect(await eventually { received.get().count == 1 })
        await settle()
        let alerts = received.get()
        #expect(alerts.map(\.messageId) == [9500])
        #expect(alerts.first?.reason == .mention)
        #expect(alerts.first?.preview == "@Alex can you?")
        #expect(alerts.first?.destination == .conversation(id: 7, targetMessageId: 9500))
    }

    @Test func webLobbyEncodingMatchesTheWebClient() throws {
        let state = WebCallHandoff.LobbyState(
            calendarEventId: nil,
            conversationId: "7",
            isPublisher: true,
            isOneToOneCall: true
        )
        #expect(
            state.json
                == #"{"calenderEventId":null,"relatedChatConversationId":"7","isPublisher":true,"isOneToOneCall":true}"#
        )
        let base = try #require(URL(string: "https://web.example.test"))
        let url = try #require(WebCallHandoff.lobbyURL(base: base, roomId: "room 1/a", state: state))
        #expect(url.absoluteString.hasPrefix("https://web.example.test/lobby/room%201%2Fa?state="))
        let encoded = try #require(url.absoluteString.components(separatedBy: "state=").last?.removingPercentEncoding)
        let decoded = try #require(Data(base64Encoded: encoded).flatMap { String(data: $0, encoding: .utf8) })
        #expect(decoded.removingPercentEncoding == state.json)
        #expect(WebCallHandoff.encodeURIComponent("a b+c/é!*'()") == "a%20b%2Bc%2F%C3%A9!*'()")
    }
}
