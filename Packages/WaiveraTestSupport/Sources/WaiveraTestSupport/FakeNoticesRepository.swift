import Foundation
import WaiveraAPI
import WaiveraData

/// The demo inbox: a task assignment, an approval waiting on the person, a meeting and older
/// task news, so every filter and day group has rows.
public final class FakeNoticesRepository: NoticesRepository, @unchecked Sendable {
    private let cell: StateCell<Resource<NoticeFeed>>
    private let readEvents = AsyncBroadcaster<String?>(replays: false, keepsEveryValue: true)
    private let clock: any WaiveraClock
    public let failure = LockedValue<WaiveraError?>(nil)

    public init(items: [Notice]? = nil, clock: any WaiveraClock) {
        self.clock = clock
        let rows = items ?? Self.demo(now: DemoData.now)
        cell = StateCell(
            Resource(
                value: NoticeFeed(items: rows, unreadCount: rows.filter { !$0.isRead }.count),
                phase: .loaded,
                updatedAt: DemoData.now
            )
        )
    }

    public func feed() -> AsyncStream<Resource<NoticeFeed>> { cell.stream() }
    public func reads() -> AsyncStream<String?> { readEvents.stream() }

    public func refresh() async {
        if let error = failure.get() {
            cell.update { $0.phase = .failed(error) }
        } else {
            cell.update {
                $0.phase = .loaded
                $0.updatedAt = clock.now
            }
        }
    }

    public func markRead(id: String) async throws {
        if let error = failure.get() { throw error }
        setRead { $0.id == id }
        readEvents.send(id)
    }

    public func markAllRead() async throws {
        if let error = failure.get() { throw error }
        setRead { _ in true }
        readEvents.send(nil)
    }

    public func readElsewhere(notificationId: String?) async {
        setRead { notificationId == nil || $0.id == notificationId }
        readEvents.send(notificationId)
    }

    private func setRead(_ predicate: (Notice) -> Bool) {
        cell.update { resource in
            guard var feed = resource.value else { return }
            for index in feed.items.indices where predicate(feed.items[index]) { feed.items[index].isRead = true }
            feed.unreadCount = feed.items.filter { !$0.isRead }.count
            resource.value = feed
        }
    }

    public static func demo(now: Date) -> [Notice] {
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3_600) }
        return [
            Notice(
                id: "n1",
                kind: .taskAssigned,
                title: "Dana Cole assigned you Quarterly ISP review",
                message: "Due Friday for Jordan Lee.",
                createdAt: ago(0.5),
                isRead: false,
                taskKey: "HEA-1047"
            ),
            Notice(
                id: "n2",
                kind: .approval,
                title: "More time requested",
                message: "Priya Raman asked to move Intake packet to Nov 12.",
                createdAt: ago(3),
                isRead: false,
                taskKey: "HEA-1050",
                opensRequests: true
            ),
            Notice(
                id: "n3",
                kind: .meeting,
                title: "Care team sync starts at 2:00 PM",
                message: "Tomorrow in Room 2.",
                createdAt: ago(26),
                isRead: true,
                eventId: "evt_care_sync"
            ),
            Notice(
                id: "n4",
                kind: .taskActivity,
                title: "Marcus Hill commented on Home visit notes",
                message: "Mom asked to move Thursday's visit to the afternoon.",
                createdAt: ago(80),
                isRead: true,
                taskKey: "HEA-1053"
            ),
            Notice(
                id: "n5",
                kind: .signature,
                title: "Signature requested",
                message: "Annual training acknowledgement.",
                createdAt: ago(200),
                isRead: false,
                webPath: "/esign/requests"
            ),
        ]
    }
}
