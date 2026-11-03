// swift-tools-version: 6.2
import PackageDescription

// `WaiveraDesignTokens` holds the plain-data side of the design system (colour values,
// spacing, radii, motion and haptic selection, skeleton timing) and builds on Linux so
// its rules are unit tested without a Mac. `WaiveraDesign` is the SwiftUI layer; every
// file in it is guarded by `#if canImport(UIKit)` so `swift test` still runs on Linux.
// SwiftUI on iOS 26 can build `ForEach` rows and other view-builder closures on its
// asynchronous renderer thread. Swift 6 inserts a main-actor check into those closures, so
// they abort there (TestFlight crash 2026-11-03, the schedule's Day/Week control; Apple
// forums thread 802729, FB20692404). Turning off only the dynamic check keeps every
// compile-time concurrency check and matches how SwiftUI runs these closures.
let swiftUIClosureSettings: [SwiftSetting] = [.unsafeFlags(["-Xfrontend", "-disable-dynamic-actor-isolation"])]

let package = Package(
    name: "WaiveraDesign",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraDesign", targets: ["WaiveraDesign"]),
        .library(name: "WaiveraDesignTokens", targets: ["WaiveraDesignTokens"]),
    ],
    targets: [
        .target(name: "WaiveraDesignTokens"),
        .target(
            name: "WaiveraDesign",
            dependencies: ["WaiveraDesignTokens"],
            resources: [.process("Resources")],
            swiftSettings: swiftUIClosureSettings
        ),
        .testTarget(name: "WaiveraDesignTokensTests", dependencies: ["WaiveraDesignTokens"]),
    ]
)
