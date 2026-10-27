// swift-tools-version: 6.2
import PackageDescription

// Shared sprout_api sample payloads (copied from the native-rebuild spec), used by every
// package's tests and by demo mode. No dependencies, so any package can depend on it.
let package = Package(
    name: "WaiveraFixtures",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraFixtures", targets: ["WaiveraFixtures"]),
    ],
    targets: [
        .target(name: "WaiveraFixtures", resources: [.copy("Fixtures")]),
    ]
)
