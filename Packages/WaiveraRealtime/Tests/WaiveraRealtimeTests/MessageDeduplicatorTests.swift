import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraRealtime

struct MessageDeduplicatorTests {
    let start = Date(timeIntervalSince1970: 1_792_000_000)

    func message(_ id: Int, text: String?) -> MessageSendResponse {
        var message = MessageSendResponse(id: id, conversationId: 7)
        message.messageContent = text
        return message
    }

    /// Feeds `deliveries` (message, seconds after start) and returns each verdict.
    func verdicts(_ deliveries: [(MessageSendResponse, TimeInterval)]) -> [Bool] {
        var dedupe = MessageDeduplicator()
        return deliveries.map { dedupe.shouldProcess($0.0, now: start.addingTimeInterval($0.1)) }
    }

    @Test func repeatWithinWindowIsDropped() {
        #expect(verdicts([(message(1, text: "hi"), 0), (message(1, text: "hi"), 14)]) == [true, false])
    }

    @Test func repeatAfterWindowIsProcessed() {
        #expect(verdicts([(message(1, text: "hi"), 0), (message(1, text: "hi"), 16)]) == [true, true])
    }

    @Test func firstDeliveryWithBodyIsLetThrough() {
        let result = verdicts([(message(1, text: nil), 0), (message(1, text: "hi"), 1), (message(1, text: "hi"), 2)])
        #expect(result == [true, true, false])
    }

    @Test func memoryIsBounded() {
        var deliveries = (0...MessageDeduplicator.capacity).map { (message($0, text: "x"), TimeInterval(0)) }
        deliveries.append((message(0, text: "x"), 0))
        // The oldest entry was evicted, so it is processed again.
        #expect(verdicts(deliveries).last == true)
    }

    @Test func messagesWithoutConversationAreDropped() {
        #expect(verdicts([(MessageSendResponse(id: 1, conversationId: nil), 0)]) == [false])
    }
}
