// swift-tools-version: 6.2
import PackageDescription

// One library per feature. Features depend on core packages, never on each other; the app
// router wires them together through the navigation closures on each entry view.
// See docs/architecture/app-shell.md for every route and entry view signature.
let features = ["AuthFeature", "TodayFeature", "ChatFeature", "ScheduleFeature", "ProfileFeature", "SettingsFeature"]

let package = Package(
    name: "Features",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: features.map { .library(name: $0, targets: [$0]) },
    dependencies: [
        .package(path: "../WaiveraDesign"),
        .package(path: "../WaiveraNotifications"),
    ],
    targets: features.map { name in
        var dependencies: [Target.Dependency] = [.product(name: "WaiveraDesign", package: "WaiveraDesign")]
        if name == "SettingsFeature" {
            dependencies.append(.product(name: "WaiveraNotifications", package: "WaiveraNotifications"))
        }
        return .target(name: name, dependencies: dependencies, resources: [.process("Resources")])
    }
)
