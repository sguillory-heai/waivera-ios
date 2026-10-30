import Foundation
import Testing

@testable import AuthFeature

@Suite("Legal links")
struct LegalLinksTests {
    @Test func pagesHangOffTheWebBase() throws {
        let links = try #require(LegalLinks.from(webBase: URL(string: "https://app.waivera.test")))
        #expect(links.termsOfService.absoluteString == "https://app.waivera.test/terms-of-service")
        #expect(links.privacyPolicy.absoluteString == "https://app.waivera.test/privacy-policy")
    }

    @Test func aBaseWithATrailingSlashKeepsItsPath() throws {
        let links = try #require(LegalLinks.from(webBase: URL(string: "https://waivera.test/app/")))
        #expect(links.termsOfService.absoluteString == "https://waivera.test/app/terms-of-service")
        #expect(links.privacyPolicy.absoluteString == "https://waivera.test/app/privacy-policy")
    }

    @Test func aBaseWithoutATrailingSlashResolvesAsABrowserWould() throws {
        let links = try #require(LegalLinks.from(webBase: URL(string: "https://waivera.test/app")))
        #expect(links.termsOfService.absoluteString == "https://waivera.test/terms-of-service")
    }

    @Test func noUsableBaseMeansNoLinks() {
        #expect(LegalLinks.from(webBase: nil) == nil)
        #expect(LegalLinks.from(webBase: URL(string: "waivera://today")) == nil)
        #expect(LegalLinks.from(webBase: URL(string: "file:///tmp/terms")) == nil)
        #expect(LegalLinks.from(webBase: URL(string: "javascript:alert(1)")) == nil)
    }
}
