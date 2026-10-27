import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ChatFeature

/// Mark as read from the list: optimistic, rolled back with a Retry notice when it fails (AF-08).
@MainActor
struct ChatListMarkReadTests {
    @Test("Mark as read clears the badge at once and tells the data layer")
    func markRead() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.row(41)?.unreadCount == 3 })
        harness.model.markRead(conversationId: 41)
        #expect(harness.row(41)?.unreadCount == 0)
        #expect(await eventually { harness.fakes.chat.calls.count("markRead:41") == 1 })
        // A new message after marking read shows unread again.
        await harness.fakes.chat.receive(Sample.message(id: 20_010, conversationId: 41, text: "again"))
        #expect(await eventually { harness.row(41)?.unreadCount == 1 })
    }

    @Test("A failed mark as read brings the badge back with a Retry notice")
    func markReadFailure() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.row(41)?.unreadCount == 3 })
        await harness.fakes.chat.setMarkReadFailure(.offline)
        harness.model.markRead(conversationId: 41)
        #expect(harness.row(41)?.unreadCount == 0)
        #expect(await eventually { harness.model.state.notice?.kind == .markReadFailed(conversationId: 41) })
        #expect(await eventually { harness.row(41)?.unreadCount == 3 })
        await harness.fakes.chat.setMarkReadFailure(nil)
        harness.model.markRead(conversationId: 41)
        #expect(harness.model.state.notice == nil)
        #expect(await eventually { harness.fakes.chat.calls.count("markRead:41") == 2 })
        await settle()
        #expect(harness.row(41)?.unreadCount == 0)
        #expect(harness.model.state.notice == nil)
    }

    @Test("Mark as read on a read row does nothing")
    func markReadNoop() async {
        let harness = ListHarness()
        await harness.start()
        defer { harness.stop() }
        #expect(await eventually { harness.ids.count == 5 })
        harness.model.markRead(conversationId: 58)
        await settle()
        #expect(harness.fakes.chat.calls.count("markRead:58") == 0)
    }
}
