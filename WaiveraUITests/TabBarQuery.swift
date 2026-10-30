import XCTest

/// The app draws its own tab bar (the system one is hidden), so tests find it by identifier
/// instead of `app.tabBars`.
extension XCUIApplication {
    var waiveraTabBar: XCUIElement {
        descendants(matching: .any)["tabBar"]
    }

    /// The tab buttons, left to right.
    var waiveraTabs: [XCUIElement] {
        buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'tab.'"))
            .allElementsBoundByIndex
            .sorted { $0.frame.minX < $1.frame.minX }
    }

    func waiveraTab(_ id: String) -> XCUIElement {
        buttons["tab.\(id)"]
    }
}
