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
        XCTAssertTrue(app.waiveraTab("chat").waitForExistence(timeout: 5))
        XCTAssertTrue(app.waiveraTab("chat").isSelected)
        // A push or link opened chat backs out to the inbox (the "Chats" list).
        XCTAssertTrue(app.navigationBars.buttons["Chats"].waitForExistence(timeout: 5))
    }
}
