import Foundation
import Testing

@testable import ChatFeature

@Suite("Composer echo after send")
struct ComposerEchoTests {
    private let sent = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func sentTextComingBackRightAfterSendIsAnEcho() {
        #expect(ComposerEcho.isEcho(sentAt: sent, now: sent.addingTimeInterval(0.05), old: "", new: "On my way"))
    }

    @Test func typingAfterSendIsKept() {
        #expect(!ComposerEcho.isEcho(sentAt: sent, now: sent.addingTimeInterval(0.2), old: "", new: "O"))
        #expect(!ComposerEcho.isEcho(sentAt: sent, now: sent.addingTimeInterval(0.2), old: "O", new: "On"))
        #expect(!ComposerEcho.isEcho(sentAt: sent, now: sent.addingTimeInterval(1), old: "", new: "Pasted text"))
        #expect(!ComposerEcho.isEcho(sentAt: nil, now: sent, old: "", new: "Draft restored"))
    }
}
