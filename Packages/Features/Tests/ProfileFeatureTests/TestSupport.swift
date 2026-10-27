import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ProfileFeature

/// Waits until `condition` holds, polling the main actor; fails the test after `timeout`.
@MainActor
func eventually(
    _ timeout: Duration = .seconds(3),
    sourceLocation: SourceLocation = #_sourceLocation,
    _ condition: () -> Bool
) async {
    let deadline = ContinuousClock.now + timeout
    while !condition() {
        if ContinuousClock.now >= deadline {
            Issue.record("Condition not met in time", sourceLocation: sourceLocation)
            return
        }
        try? await Task.sleep(for: .milliseconds(5))
    }
}

/// A launched fake environment on a manual clock: signed in as the demo user, hub connected.
@MainActor
func launchedFake(_ scenario: FakeDataEnvironment.Scenario = .demo) async -> FakeDataEnvironment {
    let fake = FakeDataEnvironment.make(scenario, clock: ManualClock())
    await fake.environment.launch()
    await eventually { fake.session.currentState.isSignedIn }
    return fake
}

/// Runs a model's `run()` for the duration of `body`, then cancels it like a view disappearing.
@MainActor
func whileRunning(_ run: @escaping @MainActor () async -> Void, _ body: () async throws -> Void) async rethrows {
    let task = Task { @MainActor in await run() }
    defer { task.cancel() }
    try await body()
}

func utc(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
    return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))
        ?? .distantPast
}

func calendarDate(_ year: Int, _ month: Int, _ day: Int) throws -> CalendarDate {
    try #require(CalendarDate(year: year, month: month, day: day))
}

let enUS = Locale(identifier: "en_US")

/// Bookmarks double whose toggle can fail, for the remove/undo error paths.
final class ScriptedBookmarks: BookmarksRepository, @unchecked Sendable {
    let resource: FakeResource<BookmarkList>
    let toggleFailure = LockedValue<WaiveraError?>(nil)
    let toggles = LockedValue<[Int]>([])

    init(_ bookmarks: [Bookmark], clock: any WaiveraClock) {
        resource = FakeResource(BookmarkList(bookmarks: bookmarks), clock: clock)
    }

    func bookmarks() -> AsyncStream<Resource<BookmarkList>> { resource.stream() }
    func refresh() async { await resource.refresh() }

    func toggle(messageId: Int, conversationId: Int) async throws -> Bool {
        toggles.update { $0.append(messageId) }
        if let failure = toggleFailure.get() { throw failure }
        let isSaved = !(resource.value?.bookmarks.contains { $0.id == messageId } ?? false)
        resource.mutate { list in
            if isSaved {
                list.bookmarks.insert(
                    Bookmark(message: ChatMessage(id: messageId, conversationId: conversationId)),
                    at: 0
                )
            } else {
                list.bookmarks.removeAll { $0.id == messageId }
            }
        }
        return isSaved
    }
}

/// Conversations double whose get-or-create fails.
final class FailingConversations: ConversationsRepository {
    let error: WaiveraError

    init(_ error: WaiveraError) {
        self.error = error
    }

    func conversations() -> AsyncStream<Resource<[Conversation]>> { AsyncStream { $0.finish() } }
    func refresh() async {}
    func conversation(id: Int) async throws -> Conversation { throw error }
    func typing() -> AsyncStream<[Int: [String]]> { AsyncStream { $0.finish() } }
    func totalUnread() -> AsyncStream<Int> { AsyncStream { $0.finish() } }
    func openDirectConversation(with userId: String) async throws -> Conversation { throw error }
    func createConversation(participantIds: [String]) async throws -> Conversation { throw error }
    func leave(conversationId: Int) async throws { throw error }
}
