import Foundation
import WaiveraAPI
import WaiveraData

@testable import ChatFeature

/// Builders for logic tests. Bad fixture input falls back to values no assertion accepts.
enum Fixture {
    static let chicago = TimeZone(identifier: "America/Chicago") ?? .current
    static let utc = TimeZone(identifier: "UTC") ?? .current
    static let base = instant("2026-10-20T15:00:00Z")

    static func instant(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value) ?? .distantPast
    }

    static func json(_ value: String) -> JSONValue {
        (try? JSONDecoder().decode(JSONValue.self, from: Data(value.utf8))) ?? .null
    }

    // swiftlint:disable:next function_parameter_count
    static func message(
        _ id: Int,
        author: String? = "usr_a",
        at: Date = base,
        kind: ChatMessage.Kind = .user,
        clientId: String? = nil,
        text: String? = nil,
        conversationId: Int = 1
    ) -> ChatMessage {
        var message = ChatMessage(id: id, conversationId: conversationId, createdAt: at)
        message.authorId = author
        message.kind = kind
        message.clientMessageId = clientId
        message.content = text ?? "m\(id)"
        return message
    }

    static func system(_ id: Int, _ text: String, at: Date = base, call: Int? = 3) -> ChatMessage {
        var message = message(id, author: nil, at: at, kind: .system, text: text)
        message.callRecordId = call
        return message
    }

    static func outgoing(
        _ clientId: String,
        state: OutgoingMessage.State = .sending,
        at: Date = base,
        parent: Int? = nil,
        text: String = "draft"
    ) -> OutgoingMessage {
        OutgoingMessage(
            clientMessageId: clientId,
            conversationId: 1,
            parentMessageId: parent,
            text: text,
            doc: nil,
            createdAt: at,
            state: state
        )
    }

    static func doc(_ nodes: String...) -> JSONValue {
        json(#"{"type":"doc","content":["# + nodes.joined(separator: ",") + "]}")
    }

    static func text(_ value: String, marks: String = "") -> String {
        marks.isEmpty
            ? #"{"type":"text","text":"\#(value)"}"#
            : #"{"type":"text","text":"\#(value)","marks":[\#(marks)]}"#
    }

    static func paragraph(_ inlines: String...) -> String {
        #"{"type":"paragraph","content":["# + inlines.joined(separator: ",") + "]}"
    }
}

/// Waits on real time for a condition the model reaches asynchronously.
@MainActor
func eventually(timeout: Double = 3, _ condition: @MainActor () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() {
        if Date() > deadline { return false }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return true
}
