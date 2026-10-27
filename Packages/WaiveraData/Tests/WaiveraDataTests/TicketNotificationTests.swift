import Foundation
import Testing
import WaiveraAPI

@testable import WaiveraData

@Suite("Ticket cards")
struct TicketNotificationTests {
    private func bot(_ data: JSONValue?, type: String? = TicketNotification.eventType) -> ChatMessage {
        var message = ChatMessage(id: 1, conversationId: 3)
        message.isBot = true
        message.systemEventType = type
        message.systemEventData = data
        return message
    }

    private let payload: JSONValue = .object([
        "ticketId": .string("T-1042"), "title": .string("Replace badge reader"),
        "url": .string("https://tickets.example.test/T-1042"), "priority": .string("high"),
    ])

    @Test func validPayloadWithDefaults() throws {
        let ticket = try #require(bot(payload).ticket)
        #expect(ticket.ticketId == "T-1042")
        #expect(ticket.type == "Task")
        #expect(ticket.priority == "HIGH")
        #expect(ticket.createdBy == nil)
    }

    @Test func unwrapsUpToThreeStringLayers() throws {
        let once = String(decoding: try WaiveraJSON.encoder().encode(payload), as: UTF8.self)
        let twice = String(decoding: try WaiveraJSON.encoder().encode(JSONValue.string(once)), as: UTF8.self)
        let thrice = String(decoding: try WaiveraJSON.encoder().encode(JSONValue.string(twice)), as: UTF8.self)
        let four = String(decoding: try WaiveraJSON.encoder().encode(JSONValue.string(thrice)), as: UTF8.self)
        #expect(bot(.string(once)).ticket != nil)
        #expect(bot(.string(thrice)).ticket != nil)
        #expect(bot(.string(four)).ticket == nil)
    }

    @Test func rejectsUnsafeOrIncompletePayloads() {
        var unsafe = payload.objectValue ?? [:]
        unsafe["url"] = .string("javascript:alert(1)")
        #expect(bot(.object(unsafe)).ticket == nil)
        var untitled = payload.objectValue ?? [:]
        untitled["title"] = .string("  ")
        #expect(bot(.object(untitled)).ticket == nil)
        #expect(bot(payload, type: "ticket.created").ticket == nil)
        var human = bot(payload)
        human.isBot = false
        #expect(human.ticket == nil)
    }
}
