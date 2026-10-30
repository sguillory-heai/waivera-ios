# Waivera iOS

Native SwiftUI rebuild of the Waivera mobile app (the Expo app in `waivera-mobile` is the behavior reference). The app gives staff realtime, on-the-go chat, push notifications, and schedule tracking backed by `sprout_api`. Later phases add lightweight task updates.

This file is the single source of truth for every coding agent (Claude Code, Codex, Copilot, Xcode agents). `CLAUDE.md` imports it. Keep it under 200 lines; move procedures into skills under `.claude/skills/` and file-specific rules into `.claude/rules/`.

## Stack

- Swift 6.2 with strict concurrency (complete checking, main-actor default isolation for the app target). SwiftUI first; UIKit only through `UIViewRepresentable` when SwiftUI has no equivalent.
- Minimum iOS: 17.0 (required for `@Observable` and SwiftData). Adopt iOS 26 Liquid Glass APIs behind `#available`.
- State: `@Observable` models, `@State`/`@Environment` injection. Do not add `ObservableObject`, Combine, or third-party state libraries.
- Networking: `URLSession` + `async/await`, `Codable` DTOs in the `WaiveraAPI` package. Realtime: the official SignalR Swift client against `sprout_api` `api/chatHub` and `api/videoHub`.
- Push: Firebase Cloud Messaging over APNs. Auth: Firebase Auth, tokens in Keychain only.
- Local data: SwiftData only for offline caches; the server is authoritative.
- Dependencies via Swift Package Manager only. Adding a package needs a stated reason in the PR.

## Layout

```
App/                     app target: composition root, auth gate, tab shell, banners, Firebase Messaging
Packages/
  WaiveraAPI/            DTOs, endpoints, API client, Firebase Auth REST, error mapping (mirrors sprout_api)
  WaiveraRealtime/       hub client, reconnect/backoff, typed events; WaiveraRealtimeSignalR transport
  WaiveraData/           repositories, ChatEngine, outbox, offline cache; WaiveraDataPersistence (SwiftData)
  WaiveraDesign/         WaiveraDesignTokens (Linux-tested) and the SwiftUI design system
  WaiveraRouting/        tabs, typed routes, deep links, navigation reducer, route catalog
  WaiveraNotifications/  push payloads, categories, presentation, registration; WaiveraNotificationsLive
  Features/              Auth, Today, Chat, Schedule, Profile, Settings (one module each)
  WaiveraFixtures/       shared sprout_api sample payloads (JSON, index in FIXTURES.md)
  WaiveraTestSupport/    fakes for every repository, scripted hub, demo data, preview modifier
TestSupport/Push/        simulator push payloads (`.apns`)
WaiveraTests/            app shell model tests (hosted in the app)
WaiveraUITests/          XCUITest flows and the screenshot tour against the fake server
WaiveraSnapshotTests/    design-system component snapshots
```

Features depend on `WaiveraData`, `WaiveraAPI` and `WaiveraDesign`, and read repositories from `@Environment(\.dataEnvironment)`; never on each other. `WaiveraTestSupport` is for previews and tests and is imported only inside `#if DEBUG`. Cross-feature navigation goes through the app's router. Data flow: `docs/architecture/data-layer.md`; shell: `docs/architecture/app-shell.md`.

## Commands

```bash
# Build and test (pick an installed simulator with: xcrun simctl list devices available)
xcodebuild -scheme Waivera -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme Waivera -destination 'platform=iOS Simulator,name=iPhone 17' test
swift test --package-path Packages/WaiveraData         # fast package tests, no simulator (Linux too)
swiftlint --strict && swift-format lint -r App Packages
# Simulate a push without App Store access
xcrun simctl push booted com.waivera.waivera TestSupport/Push/chat-message.apns
```

Run the narrowest test target that covers the change first, then the full scheme before pushing.

## Code standards

- Follow the Swift API Design Guidelines. Types `UpperCamelCase`, everything else `lowerCamelCase`, no Hungarian prefixes, no abbreviations except `ID`, `URL`, `API`.
- One primary type per file, named after the file. Views stay under ~150 lines; extract subviews instead of growing `body`.
- No work in view initializers or `body` (no formatting, sorting, or I/O). Precompute in the model.
- No force unwraps, `try!`, or `fatalError` outside tests and truly unreachable code.
- Use `foregroundStyle`, `NavigationStack`, `.task`, `@Observable`, `FormatStyle`. Avoid deprecated APIs even when they still compile.
- Every `Task {}` has a clear owner and cancellation path; prefer `.task` modifiers so SwiftUI cancels on disappear.
- Errors surface as typed `WaiveraError` values with a user-facing message; never show raw server text or stack traces.
- Comments explain why, not what. No commented-out code.

## API contract (sprout_api)

- `sprout_api` is the contract owner. DTOs in `WaiveraAPI` mirror its `dto/` types by name. When a field is unclear, read the C# DTO; do not guess from the Expo app.
- Push registration currently posts `provider: "expo"` to `/api/mobile-push/register`. Native builds register FCM tokens and need a matching API change; coordinate it in the same ticket.
- Decode unknown enum cases to an `.unknown` case instead of failing the whole payload.
- Never hard-code environment URLs, keys, or tenant IDs. Configuration comes from `.xcconfig` files per environment; secrets stay out of git.

## Dates and time zones

- Read `sprout_api/docs/timezone-standard.md` before any date work.
- Treat server timestamps as UTC instants. Some chat endpoints return UTC without a zone suffix; parse those as UTC explicitly.
- Present schedules and calendar items in the employee's saved time zone, not the device zone. Use named zones (`TimeZone(identifier:)`), never fixed offsets.
- Every date/time change adds or extends a test that covers a DST boundary.

## Design, motion, and feedback

- Use `WaiveraDesign` tokens only. Primary purple `#6A3DC4` (dark mode accent `#B79CFF`, dark solid fill `#8048E6`), matching the approved Android palette. No inline hex colors or magic spacing numbers.
- Support Dynamic Type through accessibility sizes, VoiceOver labels on every control, and 44×44pt minimum hit targets.
- Motion: spring animations from `WaiveraDesign.Motion`; respect `accessibilityReduceMotion`. Animations explain state changes; they never delay the user.
- Haptics through the shared `Haptics` helper (success, warning, selection) only at meaningful moments: send, receive while visible, errors, toggles.
- Optimistic UI for sends and status changes, with visible retry on failure. Show skeletons for loads over ~300ms; no blocking spinners over content.
- Confirmations use the shared styled confirmation sheet, never a bare `Alert` for destructive actions.
- Check light, dark, a small device (iPhone SE size), and the largest Dynamic Type size before calling UI done.

## Testing

- Swift Testing (`@Test`, `#expect`) for unit tests; XCTest only for UI tests and performance tests.
- Every feature model has tests for loading, empty, error, and reconnect states using `WaiveraTestSupport` fakes.
- Snapshot tests (swift-snapshot-testing) for shared components and key screens in light/dark and large type.
- UI tests run against the fake server, never against shared dev data.
- Never skip, disable, or loosen a test to get green. Fix the code or explain why the test is wrong.

## Git and delivery

- Until the first production release, work on `master`; pushing directly to `master` is allowed while there are no production users. After a live release, switch to the sprout_api convention (branch from `dev`, no direct pushes) and update this line. Commit messages start with the ticket ID: `[WAIV-2527] Add schedule list skeleton`. Use the same prefix across repos for one ticket.
- Never credit an AI tool anywhere in the repo: no `Co-Authored-By` or session trailers in commits, no "Generated with" footers or AI links in PR descriptions, comments, or code. Commits and PRs are authored by the person who owns the work.
- One logical change per PR. The PR description says what changed, how it was verified (commands, simulator, screenshots for UI), and any API dependency.
- Ticket comments are for non-technical business partners: describe user-visible behavior and impact only, no PRs, branches, or code terms.
- After delivery is merged and the integration branch build passes, remove the task's temporary branches and worktrees (see the cleanup rules in `sprout_api/AGENTS.md`).

## Safety

- Do not edit signing settings, provisioning profiles, entitlements, or `GoogleService-Info.plist` without being asked.
- Do not upload to App Store Connect or TestFlight, or change bundle IDs, without explicit approval.
- Never log tokens, message bodies, or participant personal data. Redact in debug logs too.
