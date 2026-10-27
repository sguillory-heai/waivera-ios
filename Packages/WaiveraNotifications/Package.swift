// swift-tools-version: 6.2
import PackageDescription

// `WaiveraNotifications` is Foundation only: payload parsing, deep-link targets, categories as
// data, the foreground presentation rule, tap routing, the permission primer policy and the
// push registration coordinator. It is unit tested on Linux.
// `WaiveraNotificationsLive` adapts it to UserNotifications on iOS; its files are guarded by
// `#if canImport(UserNotifications) && canImport(UIKit)`. Firebase Messaging is not a
// dependency here: the app target owns it behind `PushTokenSource`.
let package = Package(
    name: "WaiveraNotifications",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraNotifications", targets: ["WaiveraNotifications"]),
        .library(name: "WaiveraNotificationsLive", targets: ["WaiveraNotificationsLive"]),
    ],
    dependencies: [
        .package(path: "../WaiveraRouting")
    ],
    targets: [
        .target(
            name: "WaiveraNotifications",
            dependencies: [.product(name: "WaiveraRouting", package: "WaiveraRouting")]
        ),
        .target(
            name: "WaiveraNotificationsLive",
            dependencies: ["WaiveraNotifications"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "WaiveraNotificationsTests",
            dependencies: ["WaiveraNotifications"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
