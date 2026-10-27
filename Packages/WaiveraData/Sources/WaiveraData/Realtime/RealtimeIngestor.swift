import Foundation
import WaiveraAPI
import WaiveraRealtime

/// Routes hub events to the repositories that own them, and turns every new connection
/// epoch into a resync (05 §2): chats, the activity feed and every observed calendar feed.
public actor RealtimeIngestor {
    private let realtime: any RealtimeClient
    private let chat: ChatEngine
    private let activity: LiveActivityRepository
    private let bookmarks: LiveBookmarksRepository
    private let calendar: LiveCalendarRepository?
    private var tasks: [Task<Void, Never>] = []
    private var lastEpoch = 0

    public init(
        realtime: any RealtimeClient,
        chat: ChatEngine,
        activity: LiveActivityRepository,
        bookmarks: LiveBookmarksRepository,
        calendar: LiveCalendarRepository? = nil
    ) {
        self.realtime = realtime
        self.chat = chat
        self.activity = activity
        self.bookmarks = bookmarks
        self.calendar = calendar
    }

    public func start() {
        guard tasks.isEmpty else { return }
        lastEpoch = realtime.currentStatus.epoch
        let events = realtime.events()
        let statuses = realtime.statuses()
        let readStates = chat.readStates()
        tasks = [
            Task {
                for await event in events { await self.route(event) }
            },
            Task {
                for await status in statuses where status.isConnected { await self.connected(epoch: status.epoch) }
            },
            Task { [activity] in
                for await state in readStates { await activity.apply(state) }
            },
        ]
    }

    public func stop() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
    }

    func route(_ event: ChatHubEvent) async {
        switch event {
        case .activity, .activityRemoved, .readState:
            await activity.handle(event)
        case .bookmark(let update):
            await chat.handle(event)
            await bookmarks.handle(update)
        default:
            await chat.handle(event)
        }
    }

    private func connected(epoch: Int) async {
        guard epoch > lastEpoch else { return }
        lastEpoch = epoch
        await chat.resync()
        await activity.refresh()
        await calendar?.refreshObserved()
    }
}
