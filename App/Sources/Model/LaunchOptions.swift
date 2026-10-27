import Foundation
import WaiveraData
import WaiveraRouting

#if DEBUG
    import WaiveraTestSupport
#endif

/// Launch arguments for tests and screenshots. Parsed only in DEBUG builds; Release ignores them.
///
/// - `-WaiveraFakeServer [-WaiveraFakeScenario <scenario>]` — run against the fake backend and
///   hub (never shared dev data). `FakeDataEnvironment.scenario(fromArguments:)` is the only
///   parser of these two arguments.
/// - `-WaiveraRoute <name>` — open a `RouteCatalog` entry on launch (`conversation`, `sign-in`, …).
///   A state variant (`today-empty`) also picks its fake scenario unless one is given explicitly.
/// - `-WaiveraAppearance light|dark` — force the colour scheme.
/// - `-WaiveraDisableAnimations` — turn UIKit animations off so the screenshot tour settles fast.
struct LaunchOptions: Equatable, Sendable {
    #if DEBUG
        /// The fake environment to run, or `nil` for the live one.
        var fakeScenario: FakeDataEnvironment.Scenario?
    #endif
    var route: RouteCatalogEntry?
    var appearance: AppearancePreference?
    var disablesAnimations = false

    static let current = LaunchOptions.parse(ProcessInfo.processInfo.arguments)

    var usesFakeServer: Bool {
        #if DEBUG
            fakeScenario != nil
        #else
            false
        #endif
    }

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
            options.fakeScenario = FakeDataEnvironment.scenario(fromArguments: arguments)
            options.disablesAnimations = isOn("-WaiveraDisableAnimations")
            options.route = value(after: "-WaiveraRoute").flatMap(RouteCatalog.entry(named:))
            if options.fakeScenario != nil, !arguments.contains(FakeDataEnvironment.scenarioArgument),
                let routeScenario = options.route?.scenario.flatMap(FakeDataEnvironment.Scenario.init(rawValue:))
            {
                options.fakeScenario = routeScenario
            }
            options.appearance = value(after: "-WaiveraAppearance").flatMap(AppearancePreference.init(rawValue:))
        #endif
        return options
    }
}
