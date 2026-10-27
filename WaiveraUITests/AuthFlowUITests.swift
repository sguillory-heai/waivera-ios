import XCTest

/// Sign-in and the required password change, end to end against the fake server (01 §8).
/// `FakeSessionRepository.password` ("waivera-demo") is the only password the fake accepts.
final class AuthFlowUITests: XCTestCase {
    private let demoPassword = "waivera-demo"

    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor
    private func launch(scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-WaiveraFakeServer", "-WaiveraFakeScenario", scenario, "-WaiveraDisableAnimations"]
        app.launch()
        return app
    }

    @MainActor
    func testWrongPasswordShowsAMappedErrorThenTheRightOneSignsIn() {
        let app = launch(scenario: "signedOut")
        let email = app.textFields["Email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        let signIn = app.buttons["Sign in"]
        XCTAssertFalse(signIn.isEnabled, "disabled until both fields have text")

        email.tap()
        email.typeText("  alex.rivera@example.org ")
        let password = app.secureTextFields["Password"]
        password.tap()
        password.typeText("not the password")
        XCTAssertTrue(signIn.isEnabled)
        signIn.tap()

        let error = app.staticTexts["That email and password don't match. Please try again."]
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Firebase'")).firstMatch.exists)

        // Editing clears the error; the right password reaches the tabs.
        password.tap()
        // A secure field may clear itself on the first key; deleting covers both behaviours.
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        password.typeText(demoPassword)
        XCTAssertFalse(error.exists)
        app.buttons["Sign in"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }

    @MainActor
    func testRequiredPasswordChangeBlocksTheTabsUntilDone() throws {
        let app = launch(scenario: "passwordChange")
        let current = app.secureTextFields["Current password"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        // A link cannot get past the gate.
        let link = try XCTUnwrap(URL(string: "waivera://chats/7"))
        app.open(link)
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertFalse(app.tabBars.firstMatch.exists)

        current.tap()
        current.typeText(demoPassword)
        let new = app.secureTextFields["New password"]
        new.tap()
        new.typeText("a brand new phrase")
        let confirmation = app.secureTextFields["Confirm new password"]
        confirmation.tap()
        confirmation.typeText("a brand new phrase")
        app.buttons["Update password"].tap()
        XCTAssertTrue(app.tabBars.firstMatch.waitForExistence(timeout: 10))
    }
}
