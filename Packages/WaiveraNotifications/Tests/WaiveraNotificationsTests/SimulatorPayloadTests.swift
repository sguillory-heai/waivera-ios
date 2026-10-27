import Foundation
import Testing
import WaiveraRouting

@testable import WaiveraNotifications

/// Every `TestSupport/Push/*.apns` file used with `xcrun simctl push` parses to the push type it
/// is named for, so manual simulator checks exercise the same routes as the unit tests.
struct SimulatorPayloadTests {
    private static let pushDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // WaiveraNotificationsTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // WaiveraNotifications
        .deletingLastPathComponent()  // Packages
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("TestSupport/Push")

    private func payload(_ name: String) throws -> PushPayload {
        let data = try Data(contentsOf: Self.pushDirectory.appendingPathComponent(name))
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
        var userInfo: [AnyHashable: Any] = [:]
        for (key, value) in object { userInfo[key] = value }
        return PushPayloadParser.parse(userInfo: userInfo)
    }

    @Test(arguments: [
        ("chat-message.apns", Destination.conversation(42, targetMessageID: 1001)),
        ("chat-message-fixture.apns", .conversation(7, targetMessageID: 9312)),
        ("chat-message-no-preview.apns", .conversation(7, targetMessageID: 9312)),
        ("chat-message-attachment.apns", .conversation(7, targetMessageID: 9320)),
        ("chat-thread-reply.apns", .thread(rootMessageID: 9330, conversationID: 7, targetMessageID: 9331)),
        ("legacy-meeting.apns", .calendarEvent("evt_8f2b19c4")),
        ("legacy-call.apns", .conversation(7)),
        ("legacy-survey.apns", .today),
        ("unknown-type.apns", .inbox),
    ])
    func simulatorPayloadRoutes(file: String, expected: Destination) throws {
        #expect(try payload(file).destination == expected)
    }

    @Test func invalidConversationPayloadDoesNotNavigate() throws {
        #expect(try payload("chat-invalid-conversation.apns") == .invalidChat)
    }

    @Test func everyPayloadFileIsCovered() throws {
        let files = try FileManager.default.contentsOfDirectory(atPath: Self.pushDirectory.path)
            .filter { $0.hasSuffix(".apns") }
        #expect(files.count == 10)
    }
}
