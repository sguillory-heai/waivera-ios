// swift-tools-version: 6.2
import PackageDescription

let api: Target.Dependency = .product(name: "WaiveraAPI", package: "WaiveraAPI")

let package = Package(
    name: "WaiveraRealtime",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "WaiveraRealtime", targets: ["WaiveraRealtime"]),
        .library(name: "WaiveraRealtimeSignalR", targets: ["WaiveraRealtimeSignalR"]),
    ],
    dependencies: [
        .package(path: "../WaiveraAPI"),
        .package(path: "../WaiveraFixtures"),
        // Official ASP.NET Core SignalR client; pinned so a transport change is a reviewed bump.
        .package(url: "https://github.com/dotnet/signalr-client-swift", exact: "1.0.0"),
    ],
    targets: [
        .target(name: "WaiveraRealtime", dependencies: [api]),
        .target(
            name: "WaiveraRealtimeSignalR",
            dependencies: [
                "WaiveraRealtime",
                api,
                .product(name: "SignalRClient", package: "signalr-client-swift"),
            ]
        ),
        .testTarget(
            name: "WaiveraRealtimeTests",
            dependencies: ["WaiveraRealtime", api, .product(name: "WaiveraFixtures", package: "WaiveraFixtures")]
        ),
    ]
)
