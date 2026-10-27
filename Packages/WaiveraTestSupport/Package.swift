// swift-tools-version: 6.2
import PackageDescription

let api: Target.Dependency = .product(name: "WaiveraAPI", package: "WaiveraAPI")
let realtime: Target.Dependency = .product(name: "WaiveraRealtime", package: "WaiveraRealtime")
let data: Target.Dependency = .product(name: "WaiveraData", package: "WaiveraData")
let fixtures: Target.Dependency = .product(name: "WaiveraFixtures", package: "WaiveraFixtures")

let package = Package(
    name: "WaiveraTestSupport",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraTestSupport", targets: ["WaiveraTestSupport"])
    ],
    dependencies: [
        .package(path: "../WaiveraAPI"),
        .package(path: "../WaiveraRealtime"),
        .package(path: "../WaiveraData"),
        .package(path: "../WaiveraFixtures"),
    ],
    targets: [
        .target(name: "WaiveraTestSupport", dependencies: [api, realtime, data, fixtures]),
        .testTarget(name: "WaiveraTestSupportTests", dependencies: ["WaiveraTestSupport", api, realtime, data]),
    ]
)
