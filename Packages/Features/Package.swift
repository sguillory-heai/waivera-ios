// swift-tools-version: 6.2
import PackageDescription

// One library per feature. Features depend on core packages, never on each other; the app
// router wires them together through the navigation closures on each entry view.
// See docs/architecture/app-shell.md for every route and entry view signature.
//
// Every feature reads its repositories from `@Environment(\.dataEnvironment)` (WaiveraData).
// WaiveraTestSupport is linked for previews and feature tests only: import it inside
// `#if DEBUG`, never from release code paths (docs/architecture/data-layer.md).
let features = ["AuthFeature", "TodayFeature", "ChatFeature", "ScheduleFeature", "ProfileFeature", "SettingsFeature"]

let package = Package(
    name: "Features",
    defaultLocalization: "en",
    platforms: [.iOS(.v17)],
    products: features.map { .library(name: $0, targets: [$0]) },
    dependencies: [
        .package(path: "../WaiveraAPI"),
        .package(path: "../WaiveraData"),
        .package(path: "../WaiveraDesign"),
        .package(path: "../WaiveraNotifications"),
        .package(path: "../WaiveraTestSupport"),
    ],
    targets: features.map { name in
        var dependencies: [Target.Dependency] = [
            .product(name: "WaiveraAPI", package: "WaiveraAPI"),
            .product(name: "WaiveraData", package: "WaiveraData"),
            .product(name: "WaiveraDesign", package: "WaiveraDesign"),
            .product(name: "WaiveraTestSupport", package: "WaiveraTestSupport"),
        ]
        if name == "SettingsFeature" {
            dependencies.append(.product(name: "WaiveraNotifications", package: "WaiveraNotifications"))
        }
        return .target(name: name, dependencies: dependencies, resources: [.process("Resources")])
    } + [
        .testTarget(
            name: "TodayFeatureTests",
            dependencies: [
                "TodayFeature",
                .product(name: "WaiveraAPI", package: "WaiveraAPI"),
                .product(name: "WaiveraData", package: "WaiveraData"),
                .product(name: "WaiveraTestSupport", package: "WaiveraTestSupport"),
            ]
        )
    ]
)
