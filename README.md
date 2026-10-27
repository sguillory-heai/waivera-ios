# Waivera iOS

Native SwiftUI app for Waivera staff: realtime chat, push notifications and
schedules, backed by `sprout_api`.

- Agent and contributor rules: [AGENTS.md](AGENTS.md)
- Architecture decisions: [docs/adr](docs/adr)

## Requirements

- Xcode 26 or later (Swift 6.2) on macOS
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and SwiftLint: `brew install xcodegen swiftlint`

The Xcode project is generated from `project.yml` and is not committed:

```bash
xcodegen generate && open Waivera.xcodeproj
```

## Common commands

```bash
swift test --package-path Packages/WaiveraAPI        # fast package tests (also run on Linux)
swift test --package-path Packages/WaiveraRealtime
xcodebuild -project Waivera.xcodeproj -scheme Waivera \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
swiftlint --strict && xcrun swift-format lint -r App Packages WaiveraUITests
xcrun simctl push booted com.waivera.waivera TestSupport/Push/chat-message.apns
```

## Without a Mac

CI runs everything on every pull request: package tests in a Linux Swift
container, then lint, build, unit and UI tests on a GitHub macOS runner. On
Windows you can edit code and run `swift test` for `WaiveraAPI` and
`WaiveraRealtime` (Swift for Windows or WSL); anything that needs the simulator
is left to CI.
