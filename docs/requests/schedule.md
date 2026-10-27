# Schedule: requests to core, app and CI owners

The schedule feature (`ScheduleFeature`, `ScheduleFeatureTests`) did not edit these areas. Each
item says what is needed, why, and the local stand-in the feature uses until it exists. Removing
a stand-in is a small change inside `ScheduleFeature/Model`.

## Data layer (WaiveraData)

1. **Look up one event by id.** `CalendarRepository` only serves period feeds, so
   `CalendarEventView(eventID:)` cannot load an event it has not seen in a feed. The stand-in
   is `EventRangeMemory`, an in-memory record (LRU, 500 ids) of the period each event was last
   seen in. When an id is not remembered (cold start from a push or deep link), the screen
   searches the month grids for the previous, current and next month and otherwise shows "Event
   not found". Wanted: `func event(id: String) -> AsyncStream<Resource<CalendarEvent?>>`, backed
   by the cache plus a single-event endpoint if `sprout_api` has one, else the same search
   inside the repository.
2. **Fall back to America/Chicago, not the device zone.** `CurrentUser.scheduleTimeZone` falls
   back to `.current`. `spec/contract/dates.md` and `sprout_api/docs/timezone-standard.md` say
   a missing or invalid saved zone means America/Chicago. Fixed-offset identifiers (for example
   `GMT-6`) are accepted by `TimeZone(identifier:)` but are not named zones, so they should fall
   back as well. The stand-in is `ScheduleZone.resolve(savedIdentifier:)`. The remaining gap:
   in fallback mode the repository still computes its fetch interval in the device zone, so a
   device far from Chicago can miss events at the edges of the grid. Changing the fallback in
   core fixes both, and `isUsingDeviceTimeZone` would become `isUsingFallbackTimeZone`.
3. **A `now` that matches the repository's `today()`.** Features get `today()` from the
   repository but no clock, so the fake environment's demo day (1 Nov 2026) and the system
   time disagree. The stand-in is `RepositoryAlignedClock`, which puts the system time of day
   on the repository's date. Exposing `DataEnvironment.clock` (also asked for by the chat list)
   replaces it.
4. **Which conversation the event screen opens.** `app-shell.md` gives
   `CalendarEventView` an `onOpenConversation` closure, but spec 07 §7 names no chat action.
   The only conversation the data layer can reach for an event is a direct chat with the
   organizer, so the screen offers "Message organizer" (hidden for your own events) through
   `ConversationsRepository.openDirectConversation(with:)`. If the intent was the meeting's own
   chat (the handoff sends `relatedChatConversationId: null` today), that needs a
   `conversation(forEventId:)` call and a confirmed `sprout_api` endpoint. The spec owner
   should say which conversation is meant.

## Design system (WaiveraDesign)

5. **Promote the calendar metrics and milestone badge.** `CalendarMetrics` holds values the
   tokens do not have: dot 5, dot gap 3, today border 1.5, event bar 4, event card min height
   66, week cell min height 76, avatars 40/32/34, and the grid's type cap at accessibility1.
   `MilestoneAvatarView` and `MilestoneBadgeView` draw the 07 §4 avatar badge, which Today and
   Profile also show. Moving these into `WaiveraDesign` (the badge rule, `MilestoneBadge`, is
   plain Swift in `CelebrationText.swift`) lets the other features reuse them.

## App and project

6. **Run `ScheduleFeatureTests` in CI.** `Packages/Features/Package.swift` declares the target.
   Add `- package: Features/ScheduleFeatureTests` to the `Waivera` scheme's test targets in
   `project.yml`. Locally it runs on Linux too (102 tests): trim `features` in the manifest to
   `["ScheduleFeature"]` and run `swift test --package-path Packages/Features`.
7. **Snapshot coverage for the schedule.** `WaiveraSnapshotTests` depends only on
   `WaiveraDesign`. Add `- package: Features, product: ScheduleFeature` and
   `- package: WaiveraTestSupport, product: WaiveraTestSupport`. Then add a
   `ScheduleSnapshotTests` case using the existing `assertVariants` pattern (light, dark,
   accessibility5, 375 pt wide) for:
   - `ScheduleScreenView(state: SchedulePreviewStates.schedule(variant))` for every
     `SchedulePreviewStates.Schedule` case, wrapped in a `NavigationStack`;
   - `CalendarEventScreenView(state: SchedulePreviewStates.event(variant))` for every
     `SchedulePreviewStates.Event` case.

   The states are built through the production builders. `PreviewStatesTests` checks that each
   one shows what its name says. The loading cases render the skeleton after the 300 ms
   `LoadingContent` delay, so the snapshot should wait for it or the design system should offer
   an immediate-skeleton switch.
8. **Screenshot tour and route catalog.** The tour has no state variants, so it cannot show the
   empty, failed, fallback-zone or event-detail states. Two additions would cover spec 07's state
   list: a per-stop scenario switch (`.empty`, `.failing`), and `RouteCatalog` entries for
   `calendarEvent/evt_demo_invite` and `calendarEvent/evt_demo_checkin`.

## Spec

9. **Fallback zone conflict.** 07 §6 says to fall back to the device zone; `dates.md` says
   America/Chicago. The feature follows `dates.md` and shows a notice when the fallback is in
   effect. 07 §6 should be updated to match.
