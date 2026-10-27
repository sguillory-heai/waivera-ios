// swift-tools-version: 6.2
import PackageDescription

// Typed routes, `waivera://` deep-link parsing and the navigation reducer. Foundation only,
// so every routing rule is unit tested on Linux.
let package = Package(
    name: "WaiveraRouting",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraRouting", targets: ["WaiveraRouting"])
    ],
    targets: [
        .target(name: "WaiveraRouting"),
        .testTarget(name: "WaiveraRoutingTests", dependencies: ["WaiveraRouting"]),
    ]
)
