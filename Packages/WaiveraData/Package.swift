// swift-tools-version: 6.2
import PackageDescription

let api: Target.Dependency = .product(name: "WaiveraAPI", package: "WaiveraAPI")
let realtime: Target.Dependency = .product(name: "WaiveraRealtime", package: "WaiveraRealtime")

let package = Package(
    name: "WaiveraData",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraData", targets: ["WaiveraData"]),
        // SwiftData store; empty where SwiftData is unavailable (Linux CI).
        .library(name: "WaiveraDataPersistence", targets: ["WaiveraDataPersistence"]),
    ],
    dependencies: [
        .package(path: "../WaiveraAPI"),
        .package(path: "../WaiveraRealtime"),
        .package(path: "../WaiveraFixtures"),
    ],
    targets: [
        .target(name: "WaiveraData", dependencies: [api, realtime]),
        .target(name: "WaiveraDataPersistence", dependencies: ["WaiveraData"]),
        .testTarget(
            name: "WaiveraDataTests",
            dependencies: [
                "WaiveraData", api, realtime, .product(name: "WaiveraFixtures", package: "WaiveraFixtures"),
            ]
        ),
    ]
)
