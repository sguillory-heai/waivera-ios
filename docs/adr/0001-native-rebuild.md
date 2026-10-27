# 0001: Rebuild natively instead of staying cross-platform

Status: Accepted (2026-10-27)

## Context

The existing Waivera mobile app is an Expo / React Native app (`waivera-mobile`). The
product's value on a phone is realtime chat, push notifications and schedule tracking,
with lightweight task updates to come. Much of that app's device work went into keyboard
handling, inverted lists and loosely typed API payloads.

## Decision

Rebuild as two native apps: Swift and SwiftUI here, Kotlin and Jetpack Compose in
`waivera-android`. No runtime code is shared. What is shared is the contract: sprout_api's
REST DTOs, the chat hub's method and event names, the push payload format, and one
feature spec per slice.

Kotlin Multiplatform was considered and deferred: Swift export is still Alpha and debugging
shared code from Xcode is weak. `WaiveraAPI` and `WaiveraRealtime` stay Foundation-only so
they remain portable and testable on Linux.

## Consequences

- Communication notifications, Live Activities, widgets, Liquid Glass and system motion are available directly.
- Every feature is built and tested twice; each slice needs a parity check against the other app.
- The team has no Mac today, so every Simulator check runs in CI on a GitHub macOS runner until a cloud Mac is rented.
