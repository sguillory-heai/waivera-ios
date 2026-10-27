import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraRealtime

/// Sleeps for real (an hour) so a test can prove `retryNow()` cuts the wait short.
struct SlowClock: WaiveraClock {
    var now: Date { Date(timeIntervalSince1970: 1_792_000_000) }
    func sleep(for duration: Duration) async throws { try await Task.sleep(for: .seconds(3_600)) }
}

struct LiveRealtimeClientTests {
    let factory: FakeHubFactory
    let tokens = FakeTokenProvider()
    let clock = InstantClock()
    let client: LiveRealtimeClient

    init(script: [FakeHubFactory.Outcome] = []) {
        factory = FakeHubFactory(script: script)
        client = LiveRealtimeClient(
            hubURL: URL(filePath: "/api/chatHub"),
            factory: factory,
            tokens: tokens,
            clock: clock
        )
    }

    init() { self.init(script: []) }

    private func connected(epoch: Int) async -> Bool {
        let client = client
        return await eventually { client.currentStatus == RealtimeStatus(state: .connected, epoch: epoch) }
    }

    @Test func connectsAndJoinsGroupsRequestedBeforeConnecting() async {
        await client.join(conversationId: 7)
        await client.join(conversationId: 3)
        await client.start()
        #expect(await connected(epoch: 1))
        #expect(factory.calls(to: "JoinConversation").map(\.arguments) == [[3], [7]])
        #expect(tokens.forced == [false])
    }

    /// AF-11: a screen opened while the reconnect was still rejoining is joined too.
    @Test func aGroupOpenedDuringTheRejoinIsJoined() async {
        await client.join(conversationId: 7)
        let client = client
        factory.interleave.update { $0["JoinConversation"] = { await client.join(conversationId: 9) } }
        await client.start()
        #expect(await connected(epoch: 1))
        #expect(factory.calls(to: "JoinConversation").map(\.arguments) == [[7], [9]])
    }

    @Test func reconnectRejoinsGroupsAndBumpsEpoch() async {
        await client.start()
        #expect(await connected(epoch: 1))
        await client.join(conversationId: 7)
        #expect(factory.calls(to: "JoinConversation").count == 1)

        var states: [ConnectionState] = []
        let statuses = client.statuses()
        factory.latest?.close()
        #expect(await connected(epoch: 2))
        for await status in statuses {
            states.append(status.state)
            if status.epoch == 2 { break }
        }
        #expect(states.contains(.reconnecting(attempt: 1, delay: .zero)))
        #expect(factory.calls(to: "JoinConversation").count == 2)
        #expect(factory.connections.count == 2)
        // The token may have expired with the connection, so the reconnect forces a refresh.
        #expect(tokens.forced.last == true)
    }

    @Test func neverGivesUpAndCapsBackoff() async {
        let test = LiveRealtimeClientTests(script: Array(repeating: .fail, count: 15))
        await test.client.start()
        #expect(await test.connected(epoch: 1))
        #expect(test.factory.starts == 16)
        #expect(test.clock.sleeps.count == 15)
        #expect(test.clock.sleeps.allSatisfy { $0 <= ReconnectPolicy.defaultMaxDelay })
        #expect(test.tokens.forced.dropFirst().allSatisfy { $0 })
    }

    @Test func retryNowSkipsTheBackoffWait() async {
        let factory = FakeHubFactory(script: [.fail])
        let client = LiveRealtimeClient(
            hubURL: URL(filePath: "/api/chatHub"),
            factory: factory,
            tokens: tokens,
            clock: SlowClock()
        )
        await client.start()
        let waiting = await eventually {
            if case .reconnecting(attempt: 2, _) = client.currentStatus.state { return true }
            return false
        }
        #expect(waiting)
        await client.retryNow()
        #expect(await eventually { client.currentStatus.isConnected })
        await client.stop()
    }

    @Test func backgroundDisconnectsAndLongAbsenceForcesTokenRefresh() async {
        await client.start()
        #expect(await connected(epoch: 1))
        await client.setForeground(false)
        #expect(client.currentStatus.state == .disconnected)
        #expect(await eventually { factory.starts == 1 })

        clock.advance(by: LiveRealtimeClient.staleTokenInterval + 1)
        await client.setForeground(true)
        #expect(await connected(epoch: 2))
        #expect(tokens.forced == [false, true])
    }

    @Test func offlinePausesUntilTheNetworkReturns() async {
        await client.setNetworkAvailable(false)
        await client.start()
        try? await Task.sleep(for: .milliseconds(20))
        #expect(factory.starts == 0)
        #expect(client.currentStatus.state == .disconnected)
        await client.setNetworkAvailable(true)
        #expect(await connected(epoch: 1))
    }

    @Test func stopForgetsGroups() async {
        await client.join(conversationId: 7)
        await client.start()
        #expect(await connected(epoch: 1))
        await client.stop()
        #expect(client.currentStatus.state == .disconnected)
        await client.start()
        #expect(await connected(epoch: 2))
        #expect(factory.calls(to: "JoinConversation").count == 1)
    }

    @Test func groupMembershipIsReferenceCounted() async {
        await client.start()
        #expect(await connected(epoch: 1))
        await client.join(conversationId: 7)
        await client.join(conversationId: 7)
        await client.leave(conversationId: 7)
        #expect(factory.calls(to: "LeaveConversation").isEmpty)
        await client.leave(conversationId: 7)
        #expect(factory.calls(to: "JoinConversation").count == 1)
        #expect(factory.calls(to: "LeaveConversation").map(\.arguments) == [[7]])
    }

    @Test func callsFailFastWhenNotConnected() async {
        await #expect(throws: WaiveraError.realtimeUnavailable) {
            try await client.sendReaction(messageId: 1, reactionType: "👍")
        }
        let message = HubSendMessage(
            conversationId: 7,
            text: "hi",
            doc: nil,
            parentMessageId: nil,
            clientMessageId: "c1"
        )
        await #expect(throws: WaiveraError.realtimeUnavailable) { try await client.sendMessage(message) }
        await client.sendTypingStatus(conversationId: 7, isTyping: true)
        #expect(factory.calls.isEmpty)
    }

    @Test func sendMessagePassesPositionalArgumentsAndDecodesTheResult() async throws {
        factory.setResult(
            .success(.object(["id": 9400, "conversationId": 7, "clientMessageId": "c1"])),
            for: "SendMessage"
        )
        await client.start()
        #expect(await connected(epoch: 1))
        let message = HubSendMessage(
            conversationId: 7,
            text: "hi",
            doc: nil,
            parentMessageId: 12,
            clientMessageId: "c1"
        )
        let response = try await client.sendMessage(message)
        #expect(response.id == 9400)
        #expect(factory.calls(to: "SendMessage").first?.arguments == [7, "hi", .null, 12, "c1", .null])
    }

    @Test func hubExceptionsMapToTypedErrors() async {
        factory.setResult(.failure(HubInvocationError(message: "This channel is archived.")), for: "SendMessage")
        factory.setResult(
            .failure(HubInvocationError(message: "You cannot post in this conversation.")),
            for: "SendReaction"
        )
        await client.start()
        #expect(await connected(epoch: 1))
        let message = HubSendMessage(
            conversationId: 7,
            text: "hi",
            doc: nil,
            parentMessageId: nil,
            clientMessageId: nil
        )
        await #expect(throws: WaiveraError.channelArchived) { try await client.sendMessage(message) }
        await #expect(throws: WaiveraError.channelReadOnly) {
            try await client.sendReaction(messageId: 1, reactionType: "👍")
        }
    }

    @Test func duplicateMessageDeliveriesAreDropped() async {
        await client.start()
        #expect(await connected(epoch: 1))
        let events = client.events()
        let message: JSONValue = .object(["id": 9400, "conversationId": 7, "messageContent": "hi"])
        let connection = factory.latest
        connection?.emit(HubInvocation(target: "ReceiveMessage", arguments: [message]))
        connection?.emit(HubInvocation(target: "ReceiveMessage", arguments: [message]))
        connection?.emit(HubInvocation(target: "ReceiveTypingStatusForUser", arguments: [7, "u", true]))
        var received: [ChatHubEvent] = []
        for await event in events {
            received.append(event)
            if case .typing = event { break }
        }
        #expect(received.count == 2)
    }

    @Test func signedOutTokenKeepsRetryingWithoutConnecting() async {
        tokens.signOut()
        await client.start()
        #expect(await eventually { clock.sleeps.count >= 3 })
        #expect(!client.currentStatus.isConnected)
        await client.stop()
    }
}
