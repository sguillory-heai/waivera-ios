import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraRealtime

@testable import WaiveraTestSupport

func latest<T: Sendable>(_ stream: AsyncStream<T>) async -> T? {
    var iterator = stream.makeAsyncIterator()
    return await iterator.next()
}

func eventually(_ condition: @Sendable () async -> Bool) async -> Bool {
    for _ in 0..<400 {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(5))
    }
    return false
}

@Suite("Fake environment")
struct FakeEnvironmentTests {
    @Test func launchArguments() {
        #expect(FakeDataEnvironment.scenario(fromArguments: ["app"]) == nil)
        #expect(FakeDataEnvironment.scenario(fromArguments: ["app", "-WaiveraFakeServer"]) == .demo)
        #expect(
            FakeDataEnvironment.scenario(fromArguments: ["-WaiveraFakeServer", "-WaiveraFakeScenario", "empty"])
                == .empty
        )
    }

    @Test func demoSignsInAndLoads() async {
        let fakes = FakeDataEnvironment.make(clock: ManualClock())
        let environment = fakes.environment
        await environment.launch()
        if case .signedIn(let user) = environment.session.currentState {
            #expect(user.id == DemoData.viewerId)
        } else {
            Issue.record("expected signed in, got \(environment.session.currentState)")
        }
        #expect(fakes.realtime.currentStatus.isConnected)
        #expect(await latest(environment.conversations.conversations())?.isLoadingWithoutValue == true)
        await environment.conversations.refresh()
        #expect(await latest(environment.conversations.conversations())?.value?.count == 5)
        #expect(await latest(environment.conversations.totalUnread()) ?? 0 > 0)
    }

    @Test func foregroundPushIsHiddenOnlyForTheOpenConversationWithALiveHub() async {
        let fakes = FakeDataEnvironment.make(clock: ManualClock())
        let environment = fakes.environment
        await environment.launch()
        #expect(environment.alerts.shouldPresentForegroundPush(conversationId: 7))
        await environment.messages.open(conversationId: 7)
        #expect(!environment.alerts.shouldPresentForegroundPush(conversationId: 7))
        #expect(environment.alerts.shouldPresentForegroundPush(conversationId: 8))
        #expect(environment.alerts.shouldPresentForegroundPush(conversationId: nil))
        fakes.realtime.drop()
        #expect(environment.alerts.shouldPresentForegroundPush(conversationId: 7))
        fakes.realtime.connect()
        await environment.setForeground(false)
        #expect(environment.alerts.shouldPresentForegroundPush(conversationId: 7))
        await environment.setForeground(true)
        await environment.threads.open(rootMessageId: 9330, conversationId: 7)
        await environment.messages.close(conversationId: 7)
        // The thread keeps its conversation on screen.
        #expect(!environment.alerts.shouldPresentForegroundPush(conversationId: 7))
        await environment.threads.close(rootMessageId: 9330, conversationId: 7)
        #expect(environment.alerts.shouldPresentForegroundPush(conversationId: 7))
    }

    @Test func failingScenarioShowsErrorsEverywhere() async {
        let environment = FakeDataEnvironment.make(.failing, clock: ManualClock()).environment
        await environment.launch()
        await environment.conversations.refresh()
        await environment.messages.open(conversationId: 7)
        await environment.activity.refresh()
        await environment.calendar.refresh(period: .day, containing: DemoData.today)
        let error = WaiveraError.server(statusCode: 503)
        #expect(await latest(environment.conversations.conversations())?.error == error)
        #expect(await latest(environment.messages.timeline(conversationId: 7))?.error == error)
        #expect(await latest(environment.activity.feed())?.error == error)
        #expect(await latest(environment.calendar.feed(period: .day, containing: DemoData.today))?.error == error)
    }

    @Test func emptyScenario() async {
        let environment = FakeDataEnvironment.make(.empty, clock: ManualClock()).environment
        await environment.conversations.refresh()
        #expect(await latest(environment.conversations.conversations())?.isEmpty == true)
    }

    @Test func slowScenarioHoldsTheSkeletonUntilTheClockMoves() async {
        let clock = ManualClock()
        let environment = FakeDataEnvironment.make(.slow, clock: clock).environment
        let load = Task { await environment.people.refresh() }
        #expect(await eventually { clock.pendingSleepers == 1 })
        #expect(await latest(environment.people.directory())?.isLoadingWithoutValue == true)
        clock.advance(by: 0.6)
        await load.value
        #expect(await latest(environment.people.directory())?.value?.isEmpty == false)
    }

    @Test func signInGateAndSignOut() async throws {
        let fakes = FakeDataEnvironment.make(.signedOut, clock: ManualClock())
        let session = fakes.environment.session
        await fakes.environment.launch()
        #expect(session.currentState == .signedOut(nil))
        await #expect(throws: WaiveraError.auth(.invalidCredentials)) {
            try await session.signIn(email: "alex.rivera@example.com", password: "wrong")
        }
        try await session.signIn(email: "alex.rivera@example.com", password: FakeSessionRepository.password)
        if case .signedIn = session.currentState {} else { Issue.record("not signed in") }
        await session.signOut()
        #expect(session.currentState == .signedOut(nil))
        #expect(fakes.push.unregisterCount.get() == 1)
        #expect(fakes.realtime.log.stops == 1)
    }

    @Test func passwordChangeScenario() async throws {
        let fakes = FakeDataEnvironment.make(.passwordChange, clock: ManualClock())
        await fakes.environment.launch()
        if case .passwordChangeRequired = fakes.session.currentState {} else { Issue.record("no gate") }
        try await fakes.session.changePassword(current: FakeSessionRepository.password, new: "a-new-password")
        if case .signedIn = fakes.session.currentState {} else { Issue.record("gate not cleared") }
    }
}

@Suite("Fake chat")
struct FakeChatTests {
    let fakes = FakeDataEnvironment.make(clock: ManualClock())

    private func timeline(_ id: Int = 7) async -> MessageTimeline? {
        await latest(fakes.chat.timeline(conversationId: id))?.value
    }

    @Test func seededFailedSendRetries() async throws {
        await fakes.chat.open(conversationId: 7)
        let failed = try #require(await timeline()?.pending.first)
        #expect(failed.isFailed)
        await fakes.chat.retry(clientMessageId: failed.clientMessageId)
        #expect(await timeline()?.pending.isEmpty == true)
        #expect(await timeline()?.messages.last?.clientMessageId == failed.clientMessageId)
    }

    @Test func sendOutcomes() async throws {
        await fakes.chat.open(conversationId: 63)
        await fakes.chat.setSendOutcome(.hold)
        _ = await fakes.chat.send(text: "On my way", attachment: nil, conversationId: 63)
        #expect(await timeline(63)?.pending.first?.state == .sending)
        await fakes.chat.confirmPending()
        #expect(await timeline(63)?.messages.last?.bodyText == "On my way")
        await fakes.chat.setSendOutcome(.fail(.offline))
        _ = await fakes.chat.send(text: "Again", attachment: nil, conversationId: 63)
        #expect(await timeline(63)?.pending.first?.state == .failed(.offline))
        #expect(await fakes.chat.send(text: "  ", attachment: nil, conversationId: 63) == nil)
    }

    @Test func threadReplyCountsAndReactions() async throws {
        await fakes.chat.open(conversationId: 7)
        let before = await timeline()?.messages.first { $0.id == 9330 }?.threadReplyCount ?? 0
        await fakes.chat.open(rootMessageId: 9330, conversationId: 7)
        _ = await fakes.chat.reply(text: "Thanks", attachment: nil, rootMessageId: 9330, conversationId: 7)
        #expect(await timeline()?.messages.first { $0.id == 9330 }?.threadReplyCount == before + 1)
        let thread = await latest(fakes.chat.thread(rootMessageId: 9330, conversationId: 7))?.value
        #expect(thread?.replies.last?.bodyText == "Thanks")

        try await fakes.chat.toggleReaction("🎉", messageId: 9330, conversationId: 7)
        #expect(await timeline()?.messages.first { $0.id == 9330 }?.reactions.contains { $0.emoji == "🎉" } == true)
        await fakes.chat.setReactionsAvailable(false)
        await #expect(throws: WaiveraError.realtimeUnavailable) {
            try await fakes.chat.toggleReaction("👍", messageId: 9330, conversationId: 7)
        }
    }

    @Test func incomingMessagesCountUnreadUnlessOpen() async throws {
        await fakes.chat.refresh()
        let start = await latest(fakes.chat.totalUnread()) ?? 0
        var incoming = ChatMessage(id: 99_001, conversationId: 41, createdAt: DemoData.now)
        incoming.content = "Shift swap?"
        await fakes.chat.receive(incoming)
        #expect(await latest(fakes.chat.totalUnread()) == start + 1)
        #expect(await latest(fakes.chat.conversations())?.value?.first?.id == 41)
        await fakes.chat.setMarkReadFailure(.offline)
        await #expect(throws: WaiveraError.offline) { try await fakes.chat.markRead(conversationId: 41) }
        #expect(await latest(fakes.chat.conversations())?.value?.first?.unreadCount ?? 0 > 0)
        await fakes.chat.setMarkReadFailure(nil)
        try await fakes.chat.markRead(conversationId: 41)
        #expect(await latest(fakes.chat.conversations())?.value?.first?.unreadCount == 0)
    }

    @Test func singleEventLookupAndPaging() async {
        await fakes.calendar.refreshEvent(id: "evt_demo_invite")
        #expect(await latest(fakes.calendar.event(id: "evt_demo_invite"))?.value?.event?.id == "evt_demo_invite")
        await fakes.calendar.refreshEvent(id: "nope")
        #expect(await latest(fakes.calendar.event(id: "nope"))?.value == .notFound)

        let clock = ManualClock()
        let extra = ActivityItem(id: 9_999, kind: .mention, conversationId: 7, messageId: 1)
        let activity = FakeActivityRepository([], extraPages: [[extra]], clock: clock)
        await activity.refresh()
        #expect(await latest(activity.feed())?.value?.hasMore == true)
        activity.loadMoreFailure.update { $0 = .offline }
        await activity.loadMore()
        #expect(await latest(activity.feed())?.value?.loadMoreError == .offline)
        activity.loadMoreFailure.update { $0 = nil }
        await activity.loadMore()
        let feed = await latest(activity.feed())?.value
        #expect(feed?.items.map(\.id) == [9_999])
        #expect(feed?.hasMore == false)
        #expect(feed?.loadMoreError == nil)
    }

    @Test func voluntaryPasswordChangeStaysSignedIn() async throws {
        await fakes.environment.launch()
        #expect(await eventually { fakes.session.currentState.isSignedIn })
        try await fakes.session.changePassword(current: FakeSessionRepository.password, new: "a-new-password")
        #expect(fakes.session.currentState.isSignedIn)
        try await fakes.session.sendPasswordReset(email: "a@b.c")
        #expect(fakes.session.calls.count("sendPasswordReset") == 1)
    }

    @Test func typingAndScriptedHub() async {
        fakes.chat.setTyping(["usr_priya_raman"], in: 7)
        #expect(await latest(fakes.chat.typing())?[7] == ["usr_priya_raman"])
        let clock = ManualClock()
        let hub = FakeRealtimeClient(clock: clock)
        let received = LockedValue<[ChatHubEvent]>([])
        let stream = hub.events()
        let collector = Task { for await event in stream { received.update { $0.append(event) } } }
        defer { collector.cancel() }
        try? await Task.sleep(for: .milliseconds(10))
        hub.play([
            .init(.typing(TypingEvent(conversationId: 7, userId: "usr_priya_raman", isTyping: true))),
            .init(
                after: .seconds(2),
                .typing(TypingEvent(conversationId: 7, userId: "usr_priya_raman", isTyping: false))
            ),
        ])
        #expect(await eventually { received.get().count == 1 })
        #expect(await eventually { clock.pendingSleepers == 1 })
        clock.advance(by: 2)
        #expect(await eventually { received.get().count == 2 })
    }

    @Test func calendarRespondUpdatesTheFeed() async throws {
        await fakes.calendar.refresh(period: .week, containing: DemoData.today)
        try await fakes.calendar.respond(toEventId: "evt_demo_invite", accept: true)
        let feed = await latest(fakes.calendar.feed(period: .week, containing: DemoData.today))?.value
        #expect(feed?.events.first { $0.id == "evt_demo_invite" }?.viewerResponse == .accepted)
        // The week of 1 November includes the 5 November training day; the day view does not.
        #expect(feed?.events.contains { $0.id == "evt_allday_31" } == true)
        await fakes.calendar.refresh(period: .day, containing: DemoData.today)
        let day = await latest(fakes.calendar.feed(period: .day, containing: DemoData.today))?.value
        #expect(day?.events.contains { $0.id == "evt_allday_31" } == false)
        #expect(day?.events.contains { $0.id == "evt_demo_overnight" } == true)
    }
}
