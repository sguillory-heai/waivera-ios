import Foundation
import WaiveraRouting

/// Launch arguments for tests and screenshots. Parsed only in DEBUG builds; Release ignores them.
///
/// - `-WaiveraFakeServer` — run against the fake backend and hub (never shared dev data).
/// - `-WaiveraRoute <name>` — open a `RouteCatalog` entry on launch (`conversation`, `sign-in`, …).
/// - `-WaiveraAppearance light|dark` — force the colour scheme.
/// - `-WaiveraDisableAnimations` — turn UIKit animations off so the screenshot tour settles fast.
struct LaunchOptions: Equatable, Sendable {
    var usesFakeServer = false
    var route: RouteCatalogEntry?
    var appearance: AppearancePreference?
    var disablesAnimations = false

    static let current = LaunchOptions.parse(ProcessInfo.processInfo.arguments)

    static func parse(_ arguments: [String]) -> LaunchOptions {
        var options = LaunchOptions()
        #if DEBUG
            func value(after flag: String) -> String? {
                guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else {
                    return nil
                }
                return arguments[index + 1]
            }
            func isOn(_ flag: String) -> Bool {
                guard arguments.contains(flag) else { return false }
                let next = value(after: flag)?.lowercased()
                return next != "no" && next != "false" && next != "0"
            }
            options.usesFakeServer = isOn("-WaiveraFakeServer")
            options.disablesAnimations = isOn("-WaiveraDisableAnimations")
            options.route = value(after: "-WaiveraRoute").flatMap(RouteCatalog.entry(named:))
            options.appearance = value(after: "-WaiveraAppearance").flatMap(AppearancePreference.init(rawValue:))
        #endif
        return options
    }
}
