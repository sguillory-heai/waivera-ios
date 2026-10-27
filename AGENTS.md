# Waivera iOS

Native SwiftUI rebuild of the Waivera mobile app (the Expo app in `waivera-mobile` is the behavior reference). The app gives staff realtime, on-the-go chat, push notifications, and schedule tracking backed by `sprout_api`. Later phases add lightweight task updates.

This file is the single source of truth for every coding agent (Claude Code, Codex, Copilot, Xcode agents). `CLAUDE.md` imports it. Keep it under 200 lines; move procedures into skills under `.claude/skills/` and file-specific rules into `.claude/rules/`.

## Stack

- Swift 6.2 with strict concurrency (complete checking, main-actor default isolation for the app target). SwiftUI first; UIKit only through `UIViewRepresentable` when SwiftUI has no equivalent.
- Minimum iOS: 17.0 (required for `@Observable` and SwiftData). Adopt iOS 26 Liquid Glass APIs behind `#available`.
- State: `@Observable` models, `@State`/`@Environment` injection. Do not add `ObservableObject`, Combine, or third-party state libraries.
- Networking: `URLSession` + `async/await`, `Codable` DTOs in the `WaiveraAPI` package. Realtime: the official SignalR Swift client against `sprout_api` `/hubs/chat` and `/hubs/video`.
- Push: Firebase Cloud Messaging over APNs. Auth: Firebase Auth, tokens in Keychain only.
- Local data: SwiftData only for offline caches; the server is authoritative.
- Dependencies via Swift Package Manager only. Adding a package needs a stated reason in the PR.

## Layout

```
App/                 app target: entry point, DI container, scene setup
Packages/
  WaiveraAPI/        DTOs, endpoints, API client, error mapping (mirrors sprout_api)
  WaiveraRealtime/   SignalR connection, reconnect/backoff, event streams
  WaiveraDesign/     tokens, typography, haptics, motion, shared components
  Features/          Chat, Calendar, Profile, Settings (one module each)
  TestSupport/       fixtures, fake API, fake hub, snapshot helpers
WaiveraUITests/      XCUITest end-to-end flows against the fake server
```

Features depend on `WaiveraAPI`, `WaiveraRealtime`, `WaiveraDesign`; never on each other. Cross-feature navigation goes through the app's router.

## Commands

```bash
# Build and test (pick an installed simulator with: xcrun simctl list devices available)
xcodebuild -scheme Waivera -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -scheme Waivera -destination 'platform=iOS Simulator,name=iPhone 17' test
swift test --package-path Packages/WaiveraAPI          # fast package tests, no simulator
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

- Use `WaiveraDesign` tokens only. Primary purple `#7E57C2` (dark mode accent `#A78BFA`). No inline hex colors or magic spacing numbers.
- Support Dynamic Type through accessibility sizes, VoiceOver labels on every control, and 44×44pt minimum hit targets.
- Motion: spring animations from `WaiveraDesign.Motion`; respect `accessibilityReduceMotion`. Animations explain state changes; they never delay the user.
- Haptics through the shared `Haptics` helper (success, warning, selection) only at meaningful moments: send, receive while visible, errors, toggles.
- Optimistic UI for sends and status changes, with visible retry on failure. Show skeletons for loads over ~300ms; no blocking spinners over content.
- Confirmations use the shared styled confirmation sheet, never a bare `Alert` for destructive actions.
- Check light, dark, a small device (iPhone SE size), and the largest Dynamic Type size before calling UI done.

## Testing

- Swift Testing (`@Test`, `#expect`) for unit tests; XCTest only for UI tests and performance tests.
- Every feature model has tests for loading, empty, error, and reconnect states using `TestSupport` fakes.
- Snapshot tests (swift-snapshot-testing) for shared components and key screens in light/dark and large type.
- UI tests run against the fake server, never against shared dev data.
- Never skip, disable, or loosen a test to get green. Fix the code or explain why the test is wrong.

## Git and delivery

- Until the first production release, branch from and merge into `master`. After a live release, switch to the sprout_api convention (branch from `dev`) and update this line. Commit messages start with the ticket ID: `[WAIV-2527] Add schedule list skeleton`. Use the same prefix across repos for one ticket.
- Never credit an AI tool anywhere in the repo: no `Co-Authored-By` or session trailers in commits, no "Generated with" footers or AI links in PR descriptions, comments, or code. Commits and PRs are authored by the person who owns the work.
- One logical change per PR. The PR description says what changed, how it was verified (commands, simulator, screenshots for UI), and any API dependency.
- Ticket comments are for non-technical business partners: describe user-visible behavior and impact only, no PRs, branches, or code terms.
- After delivery is merged and the integration branch build passes, remove the task's temporary branches and worktrees (see the cleanup rules in `sprout_api/AGENTS.md`).

## Safety

- Do not edit signing settings, provisioning profiles, entitlements, or `GoogleService-Info.plist` without being asked.
- Do not upload to App Store Connect or TestFlight, or change bundle IDs, without explicit approval.
- Never log tokens, message bodies, or participant personal data. Redact in debug logs too.
