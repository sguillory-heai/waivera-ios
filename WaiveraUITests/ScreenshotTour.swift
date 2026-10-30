import WaiveraRouting
import XCTest

/// Visits every route in `RouteCatalog` against the fake server and saves a screenshot of each as
/// an `XCTAttachment` named `<route>__<device>-<variant>`, kept even when tests pass. Runs an
/// accessibility audit per screen and records every issue without stopping the tour.
///
/// Gate screens (sign-in, primer, …) need a fresh launch each (`-WaiveraRoute <name>`); tab
/// routes reuse one launch per variant and switch with `waivera://` links, which keeps the tour
/// fast. State variants (`today-empty`, `profile-failing`, …) reuse one launch per fake
/// scenario. Subclasses run in parallel, one per appearance / text-size variant.
class ScreenshotTourBase: XCTestCase {
    struct Variant {
        let name: String
        let appearance: String
        /// `-UIPreferredContentSizeCategoryName` value, or `nil` for the default size.
        let contentSize: String?
    }

    /// Overridden by each subclass. `nil` in the base class so it runs no tour itself.
    class var variant: Variant? { nil }

    override func setUp() {
        continueAfterFailure = true
    }

    @MainActor
    func testTour() throws {
        guard let variant = Self.variant else { return }
        let device = Self.deviceSlug
        for entry in RouteCatalog.gates {
            let app = launch(variant: variant, route: entry.name)
            capture(app, name: "\(entry.name)__\(device)-\(variant.name)")
            app.terminate()
        }
        let app = launch(variant: variant, route: "today")
        for entry in RouteCatalog.links {
            guard case .link(let link) = entry.target, let url = URL(string: link) else {
                XCTFail("Catalog entry \(entry.name) has no link")
                continue
            }
            app.open(url)
            capture(app, name: "\(entry.name)__\(device)-\(variant.name)")
        }
        app.terminate()
        for scenario in RouteCatalog.stateScenarios {
            let states = RouteCatalog.states.filter { $0.scenario == scenario }
            guard let first = states.first else { continue }
            let stateApp = launch(variant: variant, route: first.name, scenario: scenario)
            for entry in states {
                guard case .link(let link) = entry.target, let url = URL(string: link) else { continue }
                stateApp.open(url)
                capture(stateApp, name: "\(entry.name)__\(device)-\(variant.name)")
            }
            stateApp.terminate()
        }
    }

    @MainActor
    private func launch(variant: Variant, route: String, scenario: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        var arguments = [
            "-WaiveraFakeServer",
            "-WaiveraDisableAnimations",
            "-WaiveraAppearance", variant.appearance,
            "-WaiveraRoute", route,
        ]
        if let scenario {
            arguments += ["-WaiveraFakeScenario", scenario]
        }
        if let contentSize = variant.contentSize {
            arguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launchArguments = arguments
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 15), "\(route) did not launch")
        return app
    }

    @MainActor
    private func capture(_ app: XCUIApplication, name: String) {
        // Any query waits for the app to go idle, so the screenshot shows the settled screen.
        _ = app.windows.firstMatch.waitForExistence(timeout: 5)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        audit(app, screen: name)
    }

    @MainActor
    private func audit(_ app: XCUIApplication, screen: String) {
        var issues: [String] = []
        do {
            try app.performAccessibilityAudit { issue in
                let element = issue.element.map { "\($0.elementType) '\($0.label)'" } ?? "screen"
                issues.append("[\(issue.auditType)] \(issue.compactDescription) — \(element)")
                return true
            }
        } catch {
            issues.append("Audit could not run: \(error.localizedDescription)")
        }
        guard !issues.isEmpty else { return }
        let report = XCTAttachment(string: issues.joined(separator: "\n"))
        report.name = "\(screen)__accessibility"
        report.lifetime = .keepAlways
        add(report)
        XCTFail("\(issues.count) accessibility issue(s) on \(screen)")
    }

    /// `iPhone SE (3rd generation)` → `iPhone-SE-3rd-generation`.
    private static var deviceSlug: String {
        let name = ProcessInfo.processInfo.environment["SIMULATOR_DEVICE_NAME"] ?? "device"
        let allowed = name.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        return String(allowed).split(separator: "-").joined(separator: "-")
    }
}

final class ScreenshotTourLight: ScreenshotTourBase {
    override static var variant: Variant? { Variant(name: "light", appearance: "light", contentSize: nil) }
}

final class ScreenshotTourDark: ScreenshotTourBase {
    override static var variant: Variant? { Variant(name: "dark", appearance: "dark", contentSize: nil) }
}

final class ScreenshotTourAccessibilityXXXL: ScreenshotTourBase {
    override static var variant: Variant? {
        Variant(name: "ax5", appearance: "light", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
    }
}
