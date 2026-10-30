import Foundation
import SwiftUI
import Testing
import WaiveraAPI
import WaiveraData
import WaiveraNotifications
import WaiveraRouting
import WaiveraTestSupport

@testable import Waivera

private func link(_ text: String) throws -> URL {
    try #require(URL(string: text))
}

@MainActor
struct AppModelNavigationTests {
    @Test func launchRouteOpensOnSignIn() async {
        let harness = AppModelHarness(route: "settings-notifications")
        await harness.startSignedIn()
        #expect(harness.model.navigation.path(for: .today) == [.settings, .notificationSettings])
    }

    @Test func newChatSheetOpensTheConversationOnChat() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        harness.model.presentNewChat()
        #expect(harness.model.navigation.sheet == .newChat)
        harness.model.openConversationFromSheet(42)
        #expect(harness.model.navigation.sheet == nil)
        #expect(harness.model.navigation.selectedTab == .chat)
        #expect(harness.model.navigation.visibleConversationID == 42)
    }

    @Test func invalidLinksAreIgnored() async throws {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        harness.model.handle(url: try link("https://example.com/chats/7"))
        harness.model.handle(url: try link("waivera://chats/0"))
        #expect(harness.model.navigation == NavigationState())
    }

    @Test func anUnopenableLinkIsAcknowledgedEachTimeAndAValidOneIsNot() async throws {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        #expect(harness.model.unopenableLink == nil)
        harness.model.handle(url: try link("waivera://nowhere"))
        let first = try #require(harness.model.unopenableLink)
        harness.model.handle(url: try link("waivera://nowhere"))
        let second = try #require(harness.model.unopenableLink)
        #expect(first != second, "the same bad link tapped twice is acknowledged twice")
        harness.model.dismissUnopenableLink(first)
        #expect(harness.model.unopenableLink == second, "a stale timeout leaves the newer one")
        harness.model.dismissUnopenableLink(second)
        #expect(harness.model.unopenableLink == nil)
        harness.model.handle(url: try link("waivera://chats/7"))
        #expect(harness.model.unopenableLink == nil)
    }

    @Test func anUnopenableLinkWhileSignedOutIsNotShownToWhoeverSignsInNext() async throws {
        let harness = AppModelHarness(scenario: .signedOut)
        harness.model.start()
        await harness.settle()
        harness.model.handle(url: try link("waivera://nowhere"))
        #expect(harness.model.unopenableLink == nil)
        try await harness.signIn()
        #expect(harness.model.unopenableLink == nil)
    }

    @Test func chatAlertBannerOpensItsThreadAndClears() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        let alert = ChatAlert(
            conversationId: 7,
            messageId: 9331,
            reason: .threadReply,
            title: .person(name: "Priya Raman"),
            preview: "Same here",
            destination: .thread(rootMessageId: 9330, conversationId: 7, targetMessageId: 9331)
        )
        harness.fakes.alerts.emit(alert)
        #expect(await harness.until { harness.model.chatAlert == alert })
        harness.model.openChatAlert()
        #expect(harness.model.chatAlert == nil)
        #expect(
            harness.model.navigation.path(for: .chat) == [
                .conversation(conversationID: 7, targetMessageID: nil),
                .thread(rootMessageID: 9330, conversationID: 7, targetMessageID: 9331),
            ]
        )
    }

    @Test func connectionBannerFollowsTheHubAndRetries() async {
        let harness = AppModelHarness()
        await harness.startSignedIn()
        #expect(harness.model.connectionBanner == .hidden)
        harness.fakes.realtime.drop(attempt: 2)
        #expect(await harness.until { harness.model.connectionBanner == .reconnecting(attempt: 2) })
        harness.model.retryRealtime()
        #expect(await harness.until { harness.model.connectionBanner == .hidden })
        #expect(harness.fakes.realtime.log.retries == 1)
    }
}
