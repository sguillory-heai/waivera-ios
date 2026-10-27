import Foundation
import Testing
import WaiveraAPI
import WaiveraFixtures
import WaiveraRealtime

@testable import WaiveraData

@Suite("Attachments")
struct AttachmentTests {
    @Test func uploadMapsTheScanResult() async throws {
        let transport = RoutingTransport()
        await transport.set("POST api/chat/upload-attachment", .fixture("rest-chat-upload-attachment"))
        let repository = LiveAttachmentsRepository(api: makeAPI(transport))
        let attachment = try await repository.upload(
            data: Data("pdf".utf8),
            fileName: "roster.pdf",
            mimeType: "application/pdf"
        )
        #expect(attachment.name == "north-roster-wk43.pdf")
        #expect(attachment.size == 184_322)
        #expect(attachment.scanStatus == .clean)
    }

    @Test func rejectedUploadIsBlocked() async {
        let transport = RoutingTransport()
        await transport.set(
            "POST api/chat/upload-attachment",
            .json(#"{"documentUrl":"chat/x.exe","scanStatus":"rejected"}"#)
        )
        let repository = LiveAttachmentsRepository(api: makeAPI(transport))
        await #expect(throws: WaiveraError.attachmentBlocked) {
            try await repository.upload(data: Data(), fileName: "x.exe", mimeType: "application/octet-stream")
        }
    }

    @Test func downloadsAreCachedAndQuarantineIsBlocked() async throws {
        let transport = RoutingTransport()
        await transport.set("GET api/chat/message/9320/attachment", .json("file-bytes"))
        await transport.set("GET api/chat/message/9321/attachment", .status(423))
        let repository = LiveAttachmentsRepository(api: makeAPI(transport))
        async let first = repository.data(forMessageId: 9320)
        async let second = repository.data(forMessageId: 9320)
        #expect(try await first == Data("file-bytes".utf8))
        #expect(try await second == Data("file-bytes".utf8))
        _ = try await repository.data(forMessageId: 9320)
        #expect(await transport.count("GET api/chat/message/9320/attachment") == 1)
        await #expect(throws: WaiveraError.attachmentBlocked) { try await repository.data(forMessageId: 9321) }
    }
}

@Suite("Realtime ingestor")
struct IngestorTests {
    @Test func everyNewEpochResyncsOpenScreens() async {
        let harness = ChatHarness()
        await harness.transport.set("GET api/chat/all", .fixture("rest-chat-get-all"))
        await harness.transport.set("GET api/chat/7/messages/pagination", jsonArray([message(1)]))
        await harness.transport.set("GET api/chat/recent-activity", .fixture("rest-chat-recent-activity"))
        await harness.begin()
        let activity = LiveActivityRepository(api: harness.api, store: harness.store, clock: harness.clock)
        let bookmarks = LiveBookmarksRepository(
            api: harness.api,
            context: SessionContext(user: alex),
            chat: harness.engine,
            clock: harness.clock
        )
        let ingestor = RealtimeIngestor(
            realtime: harness.realtime,
            chat: harness.engine,
            activity: activity,
            bookmarks: bookmarks
        )
        await ingestor.start()
        await harness.engine.open(conversationId: 7)
        await settle()
        harness.realtime.connect()
        #expect(await eventually { await harness.transport.count("GET api/chat/7/messages/pagination") == 2 })
        #expect(await eventually { await harness.transport.count("GET api/chat/all") == 1 })
        #expect(await eventually { await harness.transport.count("GET api/chat/recent-activity") == 1 })
        harness.realtime.drop()
        harness.realtime.connect()
        #expect(await eventually { await harness.transport.count("GET api/chat/7/messages/pagination") == 3 })

        harness.realtime.emit(.message(message(2, at: 1_792_500_000)))
        #expect(
            await eventually {
                harness.engine.timelineCells.cell(7).current.value?.messages.map(\.id) == [1, 2]
            }
        )
        await ingestor.stop()
    }
}
