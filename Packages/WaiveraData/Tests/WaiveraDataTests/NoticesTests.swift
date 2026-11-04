import Foundation
import Testing
import WaiveraAPI
import WaiveraRealtime

@testable import WaiveraData

@Suite("Notices")
struct NoticesTests {
    private let list = "GET api/notifications"
    private let count = "GET api/notifications/unread-count"

    private let page = #"""
        [
          {"id":"a1","type":"task.assigned","title":"{author} assigned you {task}","message":"Due {date} soon",
           "createdAt":"2026-11-03T15:00:00Z","read":false,
           "notificationResources":[{"resourceId":"/task/HEA-42","resourceType":"task","resourceName":"Intake review"},
                                    {"resourceId":"u1","resourceType":"user","resourceName":"Dana Cole"}]},
          {"id":7,"type":"Task Extension Request","status":"PENDING","title":"More time asked",
           "createdAt":"2026-11-02T15:00:00Z","read":false,
           "notificationResources":[{"resourceId":"/task/9","resourceType":"task"}]},
          {"id":"m1","type":"meeting","title":"Standup","actionUrl":"/calendar?eventId=ev_12",
           "createdAt":"2026-11-01T15:00:00Z","read":true,"createdByUser":{"firstName":"Ana","lastName":"Ruiz"}}
        ]
        """#

    private func make() async -> (LiveNoticesRepository, RoutingTransport) {
        let transport = RoutingTransport()
        await transport.set(list, .json(page))
        await transport.set(count, .json(#"{"data":5,"success":true}"#))
        return (LiveNoticesRepository(api: makeAPI(transport), clock: TestClock()), transport)
    }

    @Test func mapsKindsPlaceholdersAndTargets() async {
        let (repository, _) = await make()
        await repository.refresh()
        let feed = await latest(repository.feed())?.value
        #expect(feed?.unreadCount == 5)
        let items = feed?.items ?? []
        #expect(items.count == 3)
        #expect(items[0].kind == .taskAssigned)
        #expect(items[0].title == "Dana Cole assigned you Intake review")
        #expect(items[0].message == "Due soon")
        #expect(items[0].taskKey == "HEA-42")
        #expect(items[1].id == "7")
        #expect(items[1].kind == .approval)
        #expect(items[1].opensRequests)
        #expect(items[2].kind == .meeting)
        #expect(items[2].eventId == "ev_12")
    }

    @Test func markReadIsOptimisticAndRollsBack() async {
        let (repository, transport) = await make()
        await repository.refresh()
        await transport.set("PUT api/notifications/a1", .status(500))
        await #expect(throws: WaiveraError.self) { try await repository.markRead(id: "a1") }
        var feed = await latest(repository.feed())?.value
        #expect(feed?.items.first?.isRead == false)
        #expect(feed?.unreadCount == 5)
        await transport.set("PUT api/notifications/a1", .emptyOK)
        try? await repository.markRead(id: "a1")
        feed = await latest(repository.feed())?.value
        #expect(feed?.items.first?.isRead == true)
        #expect(feed?.unreadCount == 4)
    }

    @Test func readElsewhereSurvivesFailedMarkAll() async {
        let (repository, transport) = await make()
        await repository.refresh()
        await repository.readElsewhere(notificationId: "a1")
        await transport.set("PUT api/notifications/mark-all-read", .status(500))
        try? await repository.markAllRead()
        let items = await latest(repository.feed())?.value?.items ?? []
        #expect(items.first { $0.id == "a1" }?.isRead == true)
        #expect(items.first { $0.id == "7" }?.isRead == false)
    }

    /// A refresh asked for while one runs (a new bell row mid-fetch) gets one follow-up fetch,
    /// shared by every caller that asked meanwhile, instead of being dropped.
    @Test func aRefreshDuringARefreshQueuesOneFollowUp() async throws {
        let (repository, transport) = await make()
        let gate = PageGate()
        await transport.setBeforeReply { request in
            guard request.url?.path.hasSuffix("api/notifications") == true else { return }
            await gate.wait()
        }
        let first = Task { await repository.refresh() }
        while await gate.waiting == 0 { try await Task.sleep(for: .milliseconds(2)) }
        let second = Task { await repository.refresh() }
        let third = Task { await repository.refresh() }
        try await Task.sleep(for: .milliseconds(20))
        await gate.open()
        await first.value
        await second.value
        await third.value
        #expect(await transport.count(list) == 2)
        await repository.refresh()
        #expect(await transport.count(list) == 3)
    }

    /// The hub's `ReceiveNotificationRead`: only `all: true` reads every row; a single read
    /// without a usable id is ignored instead of read as "all".
    @Test func aHubReadWithoutAnIdIsIgnored() async {
        let harness = ChatHarness()
        await harness.transport.set(list, .json(page))
        await harness.transport.set(count, .json(#"{"data":5,"success":true}"#))
        let notices = LiveNoticesRepository(api: harness.api, clock: TestClock())
        let ingestor = RealtimeIngestor(
            realtime: harness.realtime,
            chat: harness.engine,
            activity: LiveActivityRepository(api: harness.api, store: harness.store, clock: harness.clock),
            bookmarks: LiveBookmarksRepository(
                api: harness.api,
                context: SessionContext(user: CurrentUser(id: "u-alex", firebaseUid: "fb-alex")),
                chat: harness.engine,
                clock: harness.clock
            ),
            notices: notices
        )
        await notices.refresh()
        await ingestor.route(.notificationRead(NotificationReadDto(notificationId: nil, all: false)))
        await ingestor.route(.notificationRead(NotificationReadDto(notificationId: "  ", all: false)))
        #expect(await latest(notices.feed())?.value?.unreadCount == 5)
        await ingestor.route(.notificationRead(NotificationReadDto(notificationId: "a1", all: false)))
        #expect(await latest(notices.feed())?.value?.unreadCount == 4)
        await ingestor.route(.notificationRead(NotificationReadDto(notificationId: nil, all: true)))
        #expect(await latest(notices.feed())?.value?.unreadCount == 0)
    }

    @Test func renderDropsUnknownPlaceholders() {
        #expect(NoticeMapping.render("Hi {name}, see {task}", resources: []) == "Hi , see")
        #expect(NoticeMapping.render("{author} commented", resources: [], author: "Lee") == "Lee commented")
    }
}
