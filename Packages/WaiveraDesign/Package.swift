// swift-tools-version: 6.2
import PackageDescription

// iOS only: the tokens are built on SwiftUI and UIKit dynamic colours. The app
// build in CI compiles it; there is no Linux or macOS target.
let package = Package(
    name: "WaiveraDesign",
    platforms: [.iOS(.v17)],
    products: [
        .library(name: "WaiveraDesign", targets: ["WaiveraDesign"]),
    ],
    targets: [
        .target(name: "WaiveraDesign"),
    ]
)
