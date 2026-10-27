# Core requests from profile, people, bookmarks and settings (iOS)

Owner of the asking code: `Packages/Features/Sources/ProfileFeature/` and `SettingsFeature/`.
Each request says what the feature does today without it, so nothing is blocked on merge.

## 1. Organization lookup must not fall back to the session organization

- **Where:** `WaiveraData` `LiveProfileRepository.organization`.
- **Today:** when the profile's organization id does not match, it returns the session's organization.
- **Spec:** 08 §5 says to match by id only and show "Organization details unavailable" on a miss.
- **Ask:** return `nil` on an id miss.
- **Feature today:** `OrganizationContentView` already renders `nil` as unavailable, so the fix needs no feature change.

## 2. Profile sections load and fail independently

- **Where:** `ProfileRepository.ownProfile()`, a single `Resource<OwnProfile>`.
- **Today:**
  - A failure of time off or employee files is swallowed. The section just disappears.
  - A profile failure fails the whole screen.
- **Spec:** 08 §2–4 says each card loads on its own, with its own skeleton and retry.
- **Ask:** one of these two:
  - a `Resource` for each section (profile, time off, files);
  - per-section `phase` values inside `OwnProfile`.
- **Feature today:** it treats a nil `timeOff` or empty `files` as "omit the card".

## 3. Missing profile fields

- **Where:** `EmployeeProfile` and its mapper.
- **Ask:** add SCID, waiver families and agencies, which 08 §3 lists under professional details.
- **Feature today:** the rows are absent. `DetailRow` would show "—" and speak "not provided" once the fields exist.

## 4. Notification preferences per meaning

- **Where:** `NotificationPreferences` and the settings store.
- **Today:**
  - The store has `mentions`, `reactions`, `activeCalls` and `chatMessages`.
  - It has no flags for schedule reminders, schedule changes or the digest.
- **Feature today:**
  - The feature maps two meanings onto the existing flags (`NotificationSwitches`):
    - Messages sets mentions and active calls.
    - Group activity sets reactions.
  - The schedule and digest meanings are not offered.
- **Ask:**
  - one stored flag for each `NotificationMeaning` (`schedule_reminders`, `schedule_changes`, `digest`);
  - matching keys in the push registration and preferences API, coordinated with sprout_api.

## 5. Voluntary change password

- **Where:** `SessionRepository.changePassword`.
- **Today:**
  - It re-bootstraps the session.
  - It calls confirm-password-change, which is the forced-change flow, even when the user chose to change their password.
- **Ask:** one of these two:
  - a `voluntary` flag that skips the confirm call and the re-bootstrap;
  - a separate `updatePassword(current:new:)`.
- **Feature today:**
  - It calls the existing method.
  - It maps `invalidCredentials` to "current password is wrong" and `weakPassword` to "too short".

## 6. Snapshot target dependencies

- **Where:** `project.yml`, target `WaiveraSnapshotTests`.
- **Ask:** add these package products:
  - `Features/ProfileFeature`
  - `Features/SettingsFeature`
  - `WaiveraTestSupport/WaiveraTestSupport`
  - `WaiveraData/WaiveraData`
  - `WaiveraNotifications/WaiveraNotifications`
- **Feature today:** `WaiveraSnapshotTests/ProfileSettingsSnapshotTests.swift` is guarded by `#if canImport(...)`. It compiles to nothing until those products are linked, then records every screen state in light, dark and AX5.

## 7. Scheme test targets

- **Where:** `project.yml`, scheme `Waivera`, `test.targets`.
- **Ask:** add these package test targets so `xcodebuild test` runs them:
  - `package: Features/ProfileFeatureTests`
  - `package: Features/SettingsFeatureTests`

## 8. Features package on Linux

- **Today:**
  - The other feature targets import SwiftUI without a `canImport(UIKit)` guard.
  - So `swift test --package-path Packages/Features` cannot build on Linux CI or a Windows machine.
- **Ask:** guard view files the way ProfileFeature and SettingsFeature do, so pure logic tests run without a Mac.
- **Verification today:** the profile and settings tests ran on Linux against a copy of the package with only these two features.

## 9. ScreenshotTour state variants

- **Where:** the App `ScreenshotTour`.
- **Today:** it registers one state per screen.
- **Ask:** support named states, so the tour can show each state. Then register these:

  | Screen | States |
  | --- | --- |
  | Profile | loaded, refresh failed, error, unavailable |
  | People | content, no matches, empty, error |
  | Bookmarks | content, remove failed, empty, error |
  | Notifications | push off, system off |

- **Feature today:** the states exist as stateless content views (`*ContentView` and `*DisplayState`), so registering them is a one-liner each.

## 10. Bookmarks fallback progress

- **Where:** `BookmarksRepository`.
- **Today:**
  - `BookmarkList.usedFallback` is only known after the slow per-conversation fallback finishes (gap G-04).
  - Progress while it runs cannot be observed.
- **Ask:** expose a `isUsingFallback` or progress value while loading.
- **Feature today:**
  - The feature shows the skeleton while it loads.
  - When it has finished it shows a "some bookmarks may be missing" notice.
