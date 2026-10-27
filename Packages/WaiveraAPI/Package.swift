// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WaiveraAPI",
    defaultLocalization: "en",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraAPI", targets: ["WaiveraAPI"])
    ],
    dependencies: [
        .package(path: "../WaiveraFixtures")
    ],
    targets: [
        .target(name: "WaiveraAPI", resources: [.process("Resources")]),
        .testTarget(
            name: "WaiveraAPITests",
            dependencies: ["WaiveraAPI", .product(name: "WaiveraFixtures", package: "WaiveraFixtures")]
        ),
    ]
)
