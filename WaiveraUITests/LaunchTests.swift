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
        let tabBar = app.tabBars.firstMatch
        XCTAssertTrue(tabBar.waitForExistence(timeout: 15))
        let labels = tabBar.buttons.allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(labels, ["Today", "Chat", "Schedule"])
    }

    @MainActor
    func testDeepLinkOpensTheConversationOnTheChatTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-WaiveraFakeServer", "-WaiveraDisableAnimations"]
        app.launch()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 15))
        let url = try XCTUnwrap(URL(string: "waivera://chats/7?messageId=9312"))
        app.open(url)
        XCTAssertTrue(app.tabBars.buttons["Chat"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.tabBars.buttons["Chat"].isSelected)
        // A push or link opened chat backs out to the inbox (the "Chats" list).
        XCTAssertTrue(app.navigationBars.buttons["Chats"].waitForExistence(timeout: 5))
    }
}
