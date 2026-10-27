import Foundation
import Testing

@testable import WaiveraRouting

struct LinkPolicyTests {
    private func decide(_ text: String) -> LinkPolicy.Decision {
        guard let url = URL(string: text) else { return .blocked }
        return LinkPolicy.decide(url)
    }

    @Test func webLinksGoToTheBrowser() throws {
        let meet = try #require(URL(string: "https://meet.example.test/a"))
        #expect(LinkPolicy.decide(meet) == .browser(meet))
        let upper = try #require(URL(string: "HTTP://example.test"))
        #expect(LinkPolicy.decide(upper) == .browser(upper))
    }

    @Test func appLinksNavigateInsideTheApp() {
        #expect(decide("waivera://chats/7") == .navigate(.conversation(7)))
        #expect(decide("waivera://nowhere") == .blocked)
    }

    @Test func everyOtherSchemeIsBlocked() {
        for text in [
            "tel:5551234", "mailto:a@example.test", "file:///etc/hosts", "javascript:alert(1)",
            "sms:5551234", "itms-services://?action=download", "otherapp://open", "https://", "https:///path",
        ] {
            #expect(decide(text) == .blocked, "\(text)")
        }
    }
}
