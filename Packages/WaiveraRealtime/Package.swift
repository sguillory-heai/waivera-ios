// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "WaiveraRealtime",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraRealtime", targets: ["WaiveraRealtime"]),
    ],
    targets: [
        .target(name: "WaiveraRealtime"),
        .testTarget(name: "WaiveraRealtimeTests", dependencies: ["WaiveraRealtime"]),
    ]
)
