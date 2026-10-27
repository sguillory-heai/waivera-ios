// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WaiveraAPI",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraAPI", targets: ["WaiveraAPI"]),
    ],
    targets: [
        .target(name: "WaiveraAPI"),
        .testTarget(name: "WaiveraAPITests", dependencies: ["WaiveraAPI"]),
    ]
)
