# Waivera iOS

Native SwiftUI app for Waivera staff: realtime chat, push notifications and
schedules, backed by `sprout_api`.

- Agent and contributor rules: [AGENTS.md](AGENTS.md)
- Architecture decisions: [docs/adr](docs/adr)
- App shell, routes, deep links and push: [docs/architecture/app-shell.md](docs/architecture/app-shell.md)

## Requirements

- Xcode 26 or later (Swift 6.2) on macOS
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) and SwiftLint: `brew install xcodegen swiftlint`

The Xcode project is generated from `project.yml` and is not committed:

```bash
xcodegen generate && open Waivera.xcodeproj
```

## Configuration

Environment values live in `Config/Debug.xcconfig` and `Config/Release.xcconfig`. They are
**empty in git**: a fresh clone builds and runs unconfigured (a configuration-required screen,
no network, no Firebase, no push; the fake server below still works in DEBUG). For real values create the git-ignored `Config/Local.Debug.xcconfig` (and
`Config/Local.Release.xcconfig`); CI writes them from repository secrets.

| Setting | Info.plist key | Used for |
| --- | --- | --- |
| `WAIVERA_API_BASE_URL` | `WaiveraAPIBaseURL` | sprout_api root (hubs at `api/chatHub`, `api/videoHub`) |
| `WAIVERA_WEB_BASE_URL` | `WaiveraWebBaseURL` | web hand-off for calls and meetings |
| `WAIVERA_FIREBASE_API_KEY` | `WaiveraFirebaseAPIKey` | Firebase Auth REST and Messaging |
| `WAIVERA_FIREBASE_APP_ID` | `WaiveraFirebaseAppID` | Messaging (`GOOGLE_APP_ID`) |
| `WAIVERA_FIREBASE_SENDER_ID` | `WaiveraFirebaseSenderID` | Messaging (`GCM_SENDER_ID`) |
| `WAIVERA_FIREBASE_PROJECT_ID` | `WaiveraFirebaseProjectID` | Messaging |

`//` starts a comment in xcconfig files, so write URLs as `https:/$()/api.example.com`.
`GoogleService-Info.plist` is never committed and not needed. Push delivery also needs the
`aps-environment` entitlement, which waits on Apple Developer account access.

## Common commands

```bash
swift test --package-path Packages/WaiveraAPI           # fast package tests (also run on Linux)
swift test --package-path Packages/WaiveraRealtime
swift test --package-path Packages/WaiveraData          # repositories, outbox, cache, session
swift test --package-path Packages/WaiveraTestSupport   # fakes and demo data
swift test --package-path Packages/WaiveraDesign        # design tokens, motion and haptic rules
swift test --package-path Packages/WaiveraRouting       # routes, deep links, navigation rules
swift test --package-path Packages/WaiveraNotifications # push payloads, presentation, registration
xcodebuild -project Waivera.xcodeproj -scheme Waivera \
  -destination 'platform=iOS Simulator,name=iPhone 17' test
swiftlint --strict && xcrun swift-format lint -r App Packages WaiveraTests WaiveraUITests WaiveraSnapshotTests
xcrun simctl push booted com.waivera.waivera TestSupport/Push/chat-message.apns
xcrun simctl openurl booted 'waivera://chats/7?messageId=9312'
```

Run against the fake server and open any screen directly (DEBUG builds only):
launch arguments `-WaiveraFakeServer -WaiveraRoute conversation`; add
`-WaiveraFakeScenario empty|failing|slow|signedOut|passwordChange` for other states. The full list is in
[app-shell.md](docs/architecture/app-shell.md#debug-launch-arguments).

## Screenshots

`ScreenshotTour` (UI tests) captures every route in light, dark and accessibility XXXL with an
accessibility audit per screen; `WaiveraSnapshotTests` snapshots the shared components. In CI
the PNGs are exported from the result bundle and uploaded as the `screenshots` artifact.

## Without a Mac

CI runs only when started by hand (Actions minutes are limited and macOS bills at 10x). One run
collects every failure: package tests in a Linux Swift container, then lint, build, UI tests, the
screenshot tour and component snapshots on a GitHub macOS runner, with logs, the result bundle and
PNG screenshots uploaded even when steps fail. Verify locally first. On Windows or Linux you can
run `swift test` for the Foundation-only packages (Swift for Windows, WSL or the `swift:6.2`
container); anything that needs the simulator is left to CI.
