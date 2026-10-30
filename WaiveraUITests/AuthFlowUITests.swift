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
        let email = app.textFields["signIn.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 15))
        // As on Android, Sign in stays enabled with empty fields: a tap explains what is missing
        // under each field instead of a dimmed button that says nothing.
        let signIn = app.buttons["signIn.submit"]
        XCTAssertTrue(signIn.isEnabled)
        signIn.tap()
        XCTAssertTrue(app.descendants(matching: .any)["screen.sign-in"].exists)
        XCTAssertFalse(app.waiveraTabBar.exists)

        email.tap()
        email.typeText("  alex.rivera@example.org ")
        let password = app.secureTextFields["signIn.password"]
        password.tap()
        password.typeText("not the password")
        signIn.tap()

        let message = "That email and password don't match. Please try again."
        let error = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", message))
            .firstMatch
        XCTAssertTrue(error.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'Firebase'")).firstMatch.exists)

        // Editing clears the error; the right password reaches the tabs.
        password.tap()
        // A secure field may clear itself on the first key; deleting covers both behaviours.
        password.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: 20))
        password.typeText(demoPassword)
        XCTAssertFalse(error.exists)
        signIn.tap()
        XCTAssertTrue(app.waiveraTabBar.waitForExistence(timeout: 10))
    }

    @MainActor
    func testRequiredPasswordChangeBlocksTheTabsUntilDone() throws {
        let app = launch(scenario: "passwordChange")
        let current = app.secureTextFields["passwordChange.current"]
        XCTAssertTrue(current.waitForExistence(timeout: 15))
        XCTAssertFalse(app.waiveraTabBar.exists)

        // A link cannot get past the gate.
        let link = try XCTUnwrap(URL(string: "waivera://chats/7"))
        app.open(link)
        XCTAssertTrue(current.waitForExistence(timeout: 5))
        XCTAssertFalse(app.waiveraTabBar.exists)

        current.tap()
        current.typeText(demoPassword)
        let new = app.secureTextFields["passwordChange.new"]
        new.tap()
        new.typeText("a brand new phrase")
        let confirmation = app.secureTextFields["passwordChange.confirmation"]
        confirmation.tap()
        confirmation.typeText("a brand new phrase")
        app.buttons["passwordChange.submit"].tap()
        XCTAssertTrue(app.waiveraTabBar.waitForExistence(timeout: 10))
    }
}
