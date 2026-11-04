import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

@Suite("Notices")
struct NoticesTests {
    private let list = "GET api/notifications"
    private let count = "GET api/notifications/unread-count"

    private let page = #"""
        [
          {"id":"a1","type":"task.assigned","title":"{author} assigned you {task}","message":"Due {date} soon",
           "createdAt":"2026-11-03T15:00:00Z","read":false,
           "notificationResources":[{"resourceId":"/task/42","resourceType":"task","resourceName":"Intake review"},
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
        #expect(items[0].taskId == "42")
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

    @Test func renderDropsUnknownPlaceholders() {
        #expect(NoticeMapping.render("Hi {name}, see {task}", resources: []) == "Hi , see")
        #expect(NoticeMapping.render("{author} commented", resources: [], author: "Lee") == "Lee commented")
    }
}
