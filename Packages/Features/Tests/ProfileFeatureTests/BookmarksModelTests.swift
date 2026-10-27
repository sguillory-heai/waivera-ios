import Foundation
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraTestSupport

@testable import ProfileFeature

private func message(
    _ id: Int,
    conversation: Int = 7,
    createdAt: String? = nil,
    text: String? = nil,
    parent: Int? = nil,
    root: Int? = nil,
    author: String? = nil
) -> ChatMessage {
    var message = ChatMessage(id: id, conversationId: conversation, createdAt: createdAt.flatMap(WaiveraInstant.parse))
    message.plaintext = text
    message.parentMessageId = parent
    message.threadRootMessageId = root
    message.author = author.map { ChatUser(id: "u-\($0)", displayName: $0) }
    return message
}

struct BookmarkRulesTests {
    @Test func zoneLessTimestampsOrderAsUTCAgainstZonedOnes() {
        // 15:00 UTC (no suffix) is later than 14:30 UTC (09:30 at -05:00).
        let rows = BookmarkRules.rows([
            Bookmark(message: message(1, createdAt: "2026-10-30T09:30:00-05:00")),
            Bookmark(message: message(2, createdAt: "2026-10-30T15:00:00")),
            Bookmark(message: message(3, createdAt: "2026-10-30T14:45:00Z")),
        ])
        #expect(rows.map(\.messageID) == [2, 3, 1])
    }

    @Test func dropsNonPositiveConversationsDeletedMessagesAndDuplicates() {
        var deleted = message(4)
        deleted.isDeleted = true
        let rows = BookmarkRules.rows([
            Bookmark(message: message(1)),
            Bookmark(message: message(2, conversation: 0)),
            Bookmark(message: message(3, conversation: -1)),
            Bookmark(message: deleted),
            Bookmark(message: message(1)),
        ])
        #expect(rows.map(\.messageID) == [1])
    }

    @Test func threadRepliesOpenAtTheRootNeverTheParent() {
        let nested = BookmarkRules.row(message(9333, parent: 9331, root: 9330))
        #expect(nested.threadRootID == 9330)
        #expect(nested.isThreadReply)
        let parentOnly = BookmarkRules.row(message(9331, parent: 9330))
        #expect(parentOnly.threadRootID == 9330)
        let rootMessage = BookmarkRules.row(message(9330))
        #expect(rootMessage.threadRootID == nil)
        let selfRooted = BookmarkRules.row(message(9330, root: 9330))
        #expect(selfRooted.threadRootID == nil)
    }

    @Test func previewPrefersTextThenPhotoThenFile() {
        #expect(BookmarkRules.preview(message(1, text: "  who is\n on call  ")) == .text("who is on call"))
        var photo = message(2)
        photo.attachment = Attachment(url: "chat/2.png", kind: .image, name: "2.png")
        #expect(BookmarkRules.preview(photo) == .photo)
        var file = message(3)
        file.attachment = Attachment(url: "chat/3.pdf", kind: .file, name: "Policy.pdf")
        #expect(BookmarkRules.preview(file) == .file(name: "Policy.pdf"))
        #expect(BookmarkRules.preview(message(4)) == .saved)
    }

    @Test func searchMatchesTextAuthorAndKindWords() {
        let words = BookmarkSearchWords()
        let reply = BookmarkRules.row(message(1, text: "Shift swap", parent: 9, author: "Priya Raman"))
        let root = BookmarkRules.row(message(2, text: "Policy update", author: "Jordan Lee"))
        #expect(BookmarkRules.matches(reply, query: "THREAD", words: words))
        #expect(!BookmarkRules.matches(root, query: "thread", words: words))
        #expect(BookmarkRules.matches(root, query: "jordan", words: words))
        #expect(BookmarkRules.matches(root, query: "policy", words: words))
        #expect(BookmarkRules.matches(root, query: "", words: words))
    }
}

@MainActor
struct BookmarksModelTests {
    private func model(_ bookmarks: [Bookmark]) async -> (BookmarksModel, ScriptedBookmarks, FakeDataEnvironment) {
        let fake = await launchedFake()
        let repository = ScriptedBookmarks(bookmarks, clock: fake.clock)
        return (BookmarksModel(bookmarks: repository, realtime: fake.realtimeStatus), repository, fake)
    }

    @Test func loadsThenShowsRows() async {
        let (model, _, _) = await model([Bookmark(message: message(1, text: "Hello"))])
        #expect(model.phase == .loading)
        await whileRunning(model.run) {
            await eventually { model.phase == .content }
            #expect(model.rows.map(\.messageID) == [1])
            #expect(model.totalCount == 1)
        }
    }

    @Test func emptySearchAndErrorStates() async {
        let (model, repository, _) = await model([])
        await whileRunning(model.run) {
            await eventually { model.phase == .empty }
            repository.resource.setValue(BookmarkList(bookmarks: [Bookmark(message: message(1, text: "Hello"))]))
            await model.refresh()
            model.query = "nothing like it"
            #expect(model.phase == .noMatches)
            model.query = ""
            #expect(model.phase == .content)
        }
        let (failing, failingRepository, _) = await self.model([])
        failingRepository.resource.setControls(FakeControls(failure: .server(statusCode: 500)))
        await whileRunning(failing.run) {
            await eventually { failing.phase == .failed(.server(statusCode: 500)) }
        }
    }

    @Test func removeIsOptimisticAndUndoSavesAgain() async {
        let (model, repository, _) = await model([
            Bookmark(message: message(1, text: "One")), Bookmark(message: message(2, text: "Two")),
        ])
        await whileRunning(model.run) {
            await eventually { model.rows.count == 2 }
            let row = model.rows[0]
            let outcome = await model.remove(row)
            #expect(outcome == .removed)
            #expect(!model.rows.contains { $0.messageID == row.messageID })
            await model.undoRemove(row)
            await eventually { model.rows.contains { $0.messageID == row.messageID } }
            #expect(repository.toggles.get() == [row.messageID, row.messageID])
        }
    }

    @Test func aFailedRemovePutsTheRowBack() async {
        let (model, repository, _) = await model([Bookmark(message: message(1, text: "One"))])
        await whileRunning(model.run) {
            await eventually { model.rows.count == 1 }
            repository.toggleFailure.update { $0 = .offline }
            let outcome = await model.remove(model.rows[0])
            #expect(outcome == .failed(.offline))
            #expect(model.rows.map(\.messageID) == [1])
            await model.undoRemove(BookmarkRules.row(message(1)))
            #expect(model.restoreError == .offline)
        }
    }

    @Test func aBookmarkRemovedElsewhereDisappearsWithoutARefresh() async {
        let (model, repository, _) = await model([
            Bookmark(message: message(1, text: "One")), Bookmark(message: message(2, text: "Two")),
        ])
        await whileRunning(model.run) {
            await eventually { model.rows.count == 2 }
            let refreshes = repository.resource.refreshCount
            repository.resource.mutate { $0.bookmarks.removeAll { $0.id == 2 } }
            await eventually { model.rows.map(\.messageID) == [1] }
            #expect(repository.resource.refreshCount == refreshes)
        }
    }

    @Test func leavingTheScreenCancelsARefreshInFlight() async {
        let (model, repository, fake) = await model([Bookmark(message: message(1, text: "One"))])
        let clock = fake.clock as? ManualClock
        repository.resource.setControls(FakeControls(latency: .seconds(30)))
        let task = Task { await model.run() }
        await eventually { (clock?.pendingSleepers ?? 0) > 0 }
        #expect(model.isRefreshing)
        task.cancel()
        await task.value
        #expect(clock?.pendingSleepers == 0)
    }

    @Test func aReconnectRefetches() async {
        let (model, repository, fake) = await model([Bookmark(message: message(1, text: "One"))])
        await whileRunning(model.run) {
            await eventually { model.phase == .content && !model.isRefreshing }
            let before = repository.resource.refreshCount
            fake.realtime.drop()
            fake.realtime.connect()
            await eventually { repository.resource.refreshCount > before }
        }
    }
}
