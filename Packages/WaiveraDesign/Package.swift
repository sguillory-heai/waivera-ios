// swift-tools-version: 6.2
import PackageDescription

// `WaiveraDesignTokens` holds the plain-data side of the design system (colour values,
// spacing, radii, motion and haptic selection, skeleton timing) and builds on Linux so
// its rules are unit tested without a Mac. `WaiveraDesign` is the SwiftUI layer; every
// file in it is guarded by `#if canImport(UIKit)` so `swift test` still runs on Linux.
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
            resources: [.process("Resources")]
        ),
        .testTarget(name: "WaiveraDesignTokensTests", dependencies: ["WaiveraDesignTokens"]),
    ]
)
