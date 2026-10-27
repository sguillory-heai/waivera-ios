# Requests from `TodayFeature`

Gaps the Today tab hit in modules it does not own. Each one has a local workaround in
`Packages/Features/Sources/TodayFeature`, which should be removed once the request lands.

## 1. The data layer's clock in `DataEnvironment` (`WaiveraData`)

Relative times ("in 25 min", "5m", "Updated 12 min ago") need the same clock the repositories
stamp `updatedAt` with. `DataEnvironment` does not expose one, so against the fake server the
screen would measure demo data (1 November 2026) against the real date.

- Request: add `clock: any WaiveraClock` to `DataEnvironment` (the live environment passes
  `SystemClock()`, `FakeDataEnvironment` passes its clock).
- Workaround: `TodayClock.resolve(for:)` returns `DemoClock()` in DEBUG builds when the calendar
  repository is `FakeCalendarRepository`, and `SystemClock()` otherwise. Models take the clock in
  their initializer, so tests pass a `ManualClock`.

## 2. Calendar resync after a reconnect (`WaiveraData`)

`RealtimeIngestor` resyncs chats and refreshes the activity feed when the hub reconnects; calendar
feeds are not refreshed, so an invitation or change made while the device was offline stays missing
until a pull to refresh.

- Request: refresh every observed calendar feed (and milestones) in the reconnect path.
- Workaround: `TodayModel` watches `realtimeStatus.banner()` and refetches its two schedule weeks
  when it goes from offline or reconnecting to hidden. Activity is left to the data layer.

## 3. Activity total unread count (`sprout_api` + `WaiveraData`)

`GET /api/chat/activity` is paged (30 per page) and returns no unread total, so the badge is only
right for the pages already loaded (11-pitfalls #26).

- Request: add `unreadCount` to the activity response (or an unread-count endpoint) and expose it
  from `ActivityRepository`.
- Workaround: after each real sync, `ActivityController` loads more pages while the oldest loaded
  page still holds an unread item, up to 5 pages. If it stops at the cap, the badge reads "N+".

## 4. Retry a failed activity page without reloading page 1 (`WaiveraData`)

After a `loadMore` failure `LiveActivityRepository` sets `phase = .failed`, and its `loadMore` guard
requires `.loaded`, so the next page can only be fetched after a full refresh.

- Request: keep the loaded phase on a page failure and report it separately (for example
  `ActivityFeed.loadMoreFailed`), so the footer's Retry fetches just that page.
- Workaround: the footer's Retry refreshes page 1 when the feed is failed, then paging resumes.

## 5. Pending invitations independent of the observed range (`WaiveraData`)

There is no query for "every invitation awaiting my answer". Today observes the week containing
today and the week after it (`CalendarPeriod.week`), so an invitation more than about two weeks out
does not show under Needs you.

- Request: `CalendarRepository.pendingInvitations()` backed by the invitations endpoint, or a
  feed for an arbitrary date range.
- Workaround: two `.week` feeds; Next up and invitations read both, de-duplicated by event id.

## 6. Screen states in the ScreenshotTour (`App`)

The ScreenshotTour has one entry per screen and no way to register state variants, so Today's
caught-up, offline, stale and error states cannot be added to it.

- Request: let a tour entry take named variants (fake scenario plus optional setup).
- Workaround: every state is covered by `WaiveraSnapshotTests/TodaySnapshotTests.swift` (light,
  dark, AX5) from the fixed `TodayPreviewStates`, and by the `#Preview`s in `TodayView.swift` and
  `ActivityView.swift`.

## 7. Paging in `FakeActivityRepository` (`WaiveraTestSupport`)

`FakeActivityRepository.loadMore()` records the call but never adds a page and the fake feed's
`hasMore` is always false, so paging cannot be exercised against the fake server.

- Request: optional extra pages in the fake (with `hasMore` set while pages remain).
- Workaround: `TodayFeatureTests` has its own `PagedActivityRepository` test double.

## 8. Run `TodayFeatureTests` in the scheme and on Linux CI (`project.yml`, CI)

`Packages/Features/Package.swift` now declares the `TodayFeatureTests` target, but the Waivera scheme
does not list it, and CI cannot `swift test` the Features package on Linux because the other
feature modules import SwiftUI unguarded.

- Request: add `- package: Features/TodayFeatureTests` to the scheme's test targets, and either a
  macOS `swift test --package-path Packages/Features --filter TodayFeatureTests` step or guard the
  other features' SwiftUI files so the package builds on Linux.
- Done in this branch (please review): `project.yml` links `TodayFeature` into
  `WaiveraSnapshotTests`, a two-line change needed for `TodaySnapshotTests`.

## Notes

- Search lives on the Activity screen only. Today shows the type chips and the Unread toggle but no
  search field, to keep the first screen short.

## Status

Recorded by the iOS platform owner after the requests were worked through.

| # | Status | Reason |
| --- | --- | --- |
| 1 | Done | `DataEnvironment.clock`; `TodayClock` was deleted. |
| 2 | Done | `RealtimeIngestor` refreshes every observed calendar feed on reconnect; the `TodayModel` refetch was removed. |
| 3 | Moved | To `sprout-api.md` §1; the 5-page pager stays until the count exists. |
| 4 | Done | `ActivityFeed.loadMoreError` keeps the loaded phase; the footer's Retry fetches just that page. |
| 5 | Moved | To `sprout-api.md` §2; the two week feeds stay. |
| 6 | Done | `today` and `activity` have `-empty`, `-failing` and `-slow` tour entries. |
| 7 | Done | `FakeActivityRepository` takes extra pages. `TodayFeatureTests` keeps its own `PagedActivityRepository`, because it is a test double that also scripts page sizes. |
| 8 | Done | The scheme runs `Features/TodayFeatureTests` and the Linux CI step runs the whole package. |
