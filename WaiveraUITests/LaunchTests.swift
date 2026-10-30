import XCTest

final class LaunchTests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    func testFakeServerLaunchShowsTheThreeTabsInOrder() {
        let app = XCUIApplication()
        app.launchArguments = ["-WaiveraFakeServer", "-WaiveraDisableAnimations"]
        app.launch()
        XCTAssertTrue(app.waiveraTabBar.waitForExistence(timeout: 15))
        let labels = app.waiveraTabs.map(\.label)
        XCTAssertEqual(labels, ["Today", "Chat", "Schedule"])
    }

    @MainActor
    func testDeepLinkOpensTheConversationOnTheChatTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-WaiveraFakeServer", "-WaiveraDisableAnimations"]
        app.launch()
        XCTAssertTrue(app.waiveraTabBar.waitForExistence(timeout: 15))
        let url = try XCTUnwrap(URL(string: "waivera://chats/7?messageId=9312"))
        app.open(url)
        // The conversation is pushed on the Chat tab; the tab bar shows on tab roots only.
        XCTAssertTrue(app.descendants(matching: .any)["composer.field"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.waiveraTabBar.exists)
        // A push or link opened chat backs out to the inbox, with the Chat tab selected.
        let back = app.navigationBars.buttons
            .matching(NSPredicate(format: "identifier == 'BackButton' OR label == 'Chats'"))
            .firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(app.waiveraTab("chat").waitForExistence(timeout: 5))
        XCTAssertTrue(app.waiveraTab("chat").isSelected)
    }
}
