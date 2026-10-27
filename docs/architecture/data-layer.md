# Data layer

How screens get data: `WaiveraData` (repositories over `WaiveraAPI` and `WaiveraRealtime`) and
`WaiveraTestSupport` (fakes and the demo environment). Spec references such as "03 §11" point
to `native-rebuild/spec/features/*`. G-numbers point to `spec/contract/gaps.md`.

```
Feature models ──▶ DataEnvironment (protocols only)
                      │
        live          ▼                         fake (DEBUG, tests, previews)
  Live*Repository, ChatEngine              Fake*Repository, FakeChatRepository
        │        │         │                     │
   APIClient  RealtimeClient  LocalStore      DemoData (fixtures through the mappers)
```

## Source of truth (ADR 0005)

[ADR 0005](../adr/0005-in-memory-actors-and-document-cache.md) records this design and
supersedes the SwiftData-as-source-of-truth line of ADR 0002:

- The source of truth for a signed-in session is a set of in-memory actors. `ChatEngine` owns
  the inbox, the timelines, the threads and the outbox.
- `LocalStore` persists JSON documents per `CacheKey` for an instant first frame and for the
  outbox. `SwiftDataLocalStore` is one row per document.

The reasons:

- A hub event, a REST page and an optimistic send must never interleave half-applied. One
  actor makes that hold.
- JSON documents never need a schema migration.
- The whole layer stays testable on Linux.

## Rules every repository follows

- **Streams replay.** Each `AsyncStream` emits the current value as soon as it is subscribed
  to, and then emits every change. A screen that subscribes late still renders.
- **`Resource<Value>`** is what lists emit. It has three parts:
  - `value`: the cached data or the server data.
  - `phase`: one of `idle`, `loading`, `loaded` or `failed(WaiveraError)`.
  - `updatedAt`: `nil` when the value only came from the cache.

  Screens map a `Resource` to a state with these helpers:

  | Screen state | Helper |
  | --- | --- |
  | Skeleton | `isLoadingWithoutValue` |
  | Empty | `isEmpty` |
  | Content | `value` |
  | Refreshing | `isRefreshing` |
  | Error | `error` |

  A failed refresh keeps the value that was already shown.
- **Errors are `WaiveraError`.** Server text is never passed through.
- **The server is authoritative.** The `LocalStore` cache is replaced by the next successful
  fetch, and sign-out wipes it.
- **Ids.** "Is this me" compares the backend user id only (`CurrentUser.isMe`,
  `ChatMessage.isMine`).
- **Timestamps.** Every timestamp is a UTC `Date`, parsed by `WaiveraInstant`. A timestamp
  without a zone suffix is read as UTC.
- **Dates.** Date-only values are `CalendarDate`. They are shown in the employee's saved
  zone (`CurrentUser.scheduleTimeZone`). The device zone is used only when no zone is
  saved, and then `isDeviceFallback` is true.
- **Concurrency.**
  - Live repositories are actors, or `Sendable` classes over a lock.
  - A sign-out bumps a `generation` counter. Any task still running from before the
    sign-out checks it and drops its result.

## Public protocols

Every protocol is in `Sources/WaiveraData/Repositories/RepositoryProtocols.swift`. Each one
has a live type and a fake type.

| Protocol | Streams | Actions | Live / fake |
| --- | --- | --- | --- |
| `SessionRepository` | `states()` → `SessionState`, `currentState` | `start`, `signIn`, `changePassword`, `retryBootstrap`, `signOut` | `LiveSessionRepository` / `FakeSessionRepository` |
| `ConversationsRepository` | `conversations()` → `Resource<[Conversation]>`, `typing()` → `[conversationId: [userId]]`, `totalUnread()` → `Int` | `refresh`, `conversation(id:)`, `openDirectConversation(with:)`, `createConversation`, `leave` | `ChatEngine` / `FakeChatRepository` |
| `MessagesRepository` (adds `MessageActions`) | `timeline(conversationId:)` → `Resource<MessageTimeline>` | `open`, `close`, `refresh`, `loadOlder`, `send`, `markRead`, `composerChanged` | `ChatEngine` / `FakeChatRepository` |
| `ThreadsRepository` (adds `MessageActions`) | `thread(rootMessageId:conversationId:)` → `Resource<ThreadTimeline>` | `open`, `close`, `refresh`, `reply`, `markRead` | `ChatEngine` / `FakeChatRepository` |
| `MessageActions` | none | `retry(clientMessageId:)`, `discard`, `edit`, `delete`, `toggleReaction` | shared by both |
| `AttachmentsRepository` | none | `upload`, `data(forMessageId:)` | `LiveAttachmentsRepository` / `FakeAttachmentsRepository` |
| `AvatarRepository` | none | `avatar(userId:)` → `Data?` | `LiveAvatarRepository` / `FakeAvatarRepository` |
| `BookmarksRepository` | `bookmarks()` → `Resource<BookmarkList>` | `refresh`, `toggle` | `LiveBookmarksRepository` / `FakeBookmarksRepository` |
| `ActivityRepository` | `feed()` → `Resource<ActivityFeed>` | `refresh`, `loadMore`, `markRead`, `markAllRead` | `LiveActivityRepository` / `FakeActivityRepository` |
| `PeopleRepository` | `directory()` → `Resource<[DirectoryPerson]>` | `refresh`, `person(id:)` | `LivePeopleRepository` / `FakePeopleRepository` |
| `CalendarRepository` | `feed(period:containing:)` → `Resource<CalendarFeed>`, `milestones()` → `Resource<MilestoneIndex>` | `scheduleTimeZone`, `today`, `refresh`, `respond`, `refreshMilestones`, `meetingURL` | `LiveCalendarRepository` / `FakeCalendarRepository` |
| `ProfileRepository` | `profile()` → `Resource<OwnProfile>` | `refresh` | `LiveProfileRepository` / `FakeProfileRepository` |
| `SettingsRepository` | `settings()` → `AppSettings`, `currentSettings` | `update` | `LiveSettingsRepository` / `FakeSettingsRepository` |
| `PushRegistrationRepository` | none | `register(token:preferences:)`, `unregister()` | `LivePushRegistrationRepository` / `FakePushRegistrationRepository` |
| `RealtimeStatusRepository` | `banner()` → `ConnectionBanner`, `statuses()` → `RealtimeStatus` | `retryNow` | `LiveRealtimeStatusRepository` / `FakeRealtimeStatusRepository` |
| `ChatAlertsRepository` | `alerts()` → `ChatAlert` (not replayed) | `shouldPresentForegroundPush(conversationId:)` | `LiveChatAlertsRepository` / `FakeChatAlertsRepository` |

`DataEnvironment` is a struct that holds one of each repository as an existential. It also
has three members:

- `callURL(conversation)`: the web lobby link for a conversation's call.
- `launch()`: starts the session.
- `setForeground(_:)`: tells the data layer whether the app is in the foreground.

### Behaviour worth knowing per protocol

**Session**
- Bootstraps once per Firebase identity. A token refresh never triggers another bootstrap.
- A 401 or 403 at bootstrap signs out and sets `.signedOut(.unauthorized)`.
- Any other bootstrap failure sets `.bootstrapFailed` and keeps Firebase signed in, so
  `retryBootstrap()` can try again.
- Gates: `.passwordChangeRequired`, then `.onboardingRequired`, then `.signedIn`.
- Sign-out runs in this order:
  1. `sessionWillEnd`: unregister push and stop realtime, while requests can still
     authenticate.
  2. Firebase sign-out.
  3. `sessionDidEnd`: clear caches and wipe the `LocalStore`.

**Conversations**
- `/api/chat/all` with `includeArchived=false` and `includeMeetings=false`, both sent
  explicitly.
- Concurrent refreshes share one request.
- Rows whose preview is blank are filled from the detail endpoint, six at a time. The unread
  count from the list is kept.
- A hub message raises the unread count unless the message is the viewer's own or that
  conversation is on screen.
- A sparse hub event never blanks a preview. It triggers a refetch instead.
- Call state is live only for `Initiated`, `Active` and `Rejoined`.

**Messages**
- `open` joins the hub group (reference counted), marks the conversation visible, shows the
  cached newest page, then fetches.
- Every reconnect refetches the newest page of each open timeline and merges it by id.
- If the refetched page does not overlap what is shown, the timeline restarts from that page
  rather than leaving a gap.
- Hub messages that arrive before the first page are buffered and merged into it.
- Thread replies never appear in the timeline.
- `loadOlder` stops when a page is short or the cursor stops moving.
- `markRead`:
  - Sends `MarkAsRead` over the hub, or over REST when the hub is disconnected.
  - Then calls read-through once per newest root message id.
  - The resulting `ChatReadState` also updates the activity feed.

**Outbox** (both `send` and `reply`)
- Every send gets a client-generated UUID, `clientMessageId`, which is the server's
  idempotency key.
- The hub is tried first, then REST.
- Transient errors are retried automatically after 1 s and then 2 s, three attempts in all.
  After that the message shows `.failed`, with Retry and Discard. A permanent error shows
  `.failed` at once.
- Retry reuses the same client id.
- Pending sends survive a relaunch: they are persisted, then resumed on sign-in, on
  reconnect and when the network returns.
- A server message confirms a pending row in one of two ways:
  - by matching client id, or
  - if the id is missing, by author, conversation, thread and text within 60 s.

**Reactions**
- Applied optimistically, then rolled back if the call fails, and the error is thrown.
- The hub is the only writer (G-01). When the hub is disconnected,
  `.realtimeUnavailable` is thrown so the screen can say so.

**Typing**
- Outgoing: `true` on the first keystroke, then at most once every 3 s while typing.
  `false` after 1.8 s idle, on send and on leaving.
- Incoming: entries expire after 5 s. They also clear when that user's message arrives and
  on every reconnect. The viewer's own typing events are ignored.

**Threads**
- Opening a thread joins the conversation's hub group, so live replies arrive even when the
  thread was opened from a push.
- The root's reply count goes up only for a reply not seen before. A full thread fetch then
  sets the exact count.
- Bookmark and activity destinations always use the thread root (`ChatDestination`).

**Calendar**
- The fetch range is the full rendered grid in the employee's zone: 1, 7 or 42 days. A
  day or grid that crosses a DST change is 23 or 25 hours longer or shorter accordingly.
- Timed events use half-open intervals.
- All-day events are `CalendarDate` spans and ignore zones.
- Invitation state:
  - The viewer's attendee row wins.
  - Otherwise `isInvitationAccept` gives true → `accepted`, false → `declined`, and
    null → `notInvited`.
  - `pending` only ever comes from an `INVITED` row.
- A Feb 29 milestone falls on Feb 28 in non-leap years.

**Push**
- `register` is debounced by 400 ms and skipped when the stored fingerprint (a digest, never
  the token itself) matches.
- Transient failures retry with backoff, up to 6 attempts.
- If `pushEnabled` is false, the device is unregistered instead.
- Provider is `fcm` and platform is `ios`.
- Sign-out unregisters and forgets the token.

**Foreground push**
- `shouldPresentForegroundPush` returns false only when two things are both true: the hub
  is connected, and that conversation is on screen with the app active.
- It is the app's only suppression rule. `AppModel.presentationDecision` asks it for chat
  pushes and hands the answer to `ForegroundPresentationPolicy` (WaiveraNotifications), which
  only adds the In-app banners and Sound switches. The fake applies the same rule over the
  fake chat's `open`/`close` and the fake hub's state.

**Ticket cards**
- `ChatMessage.ticket` parses a bot's `ticket.update` payload. It unwraps up to three layers
  of JSON strings and accepts only `http` and `https` links (03 §15).

## Models

All in `Sources/WaiveraData/Models`. Every model is `Sendable` and `Hashable`. Models that
are cached are also `Codable`.

**Chat**
- `Conversation`: `Kind`, `ChannelInfo`, `CallRoom`, `ConversationTitle`, `ConversationPreview`.
- `ChatMessage`: `Attachment`, `Reaction`, `ReactionGroup`, `TicketNotification`.
- `ChatUser`, `ChatDestination`.
- `MessageTimeline`, `ThreadTimeline`.
- `OutgoingMessage`, with `State` of `sending`, `queued(attempt)` or `failed`.

**Activity and bookmarks**
- `ActivityItem`, `ActivityFeed`, `Bookmark`, `BookmarkList` (`usedFallback`).

**Session and people**
- `CurrentUser`, `Organization`, `SessionState`.
- `DirectoryPerson`, `PersonProfile`, `EmployeeProfile`, `TimeOffOverview`, `TimeOffEntry`,
  `EmployeeFile`, `OwnProfile`.

**Calendar**
- `CalendarEvent` (`AllDaySpan`), `CalendarAttendee`, `InvitationState`, `CalendarTimeOff`,
  `Holiday`, `CalendarFeed`, `DayAgenda`, `CalendarPeriod`.
- `Milestone`, `MilestoneIndex`, `Celebration`.

**Settings and realtime**
- `NotificationPreferences`, `AppSettings`, `AppearancePreference`.
- `ConnectionBanner`, `ChatAlert`.

**Mappers**
- `ChatMapper`, `CalendarMapper` and `ProfileMapper` are the only way DTOs become models.
  `DemoData` uses them too, so fakes and live code render the same shapes.

## Live composition (what the app target does)

`App/Sources/Composition/DataLayerBridge.swift` builds the environment once, from
`CompositionRoot`:

```swift
guard case .success(let apiConfiguration) = WaiveraConfiguration.load(from: configuration.infoDictionary)
else { return nil }  // the configuration-missing gate
let localStore: any LocalStore
if let store = try? SwiftDataLocalStore.make() {
    localStore = store
} else {
    localStore = InMemoryLocalStore()
}
return DataEnvironment.live(
    LiveDependencies(
        configuration: apiConfiguration,
        tokenStore: KeychainTokenStore(),
        hubFactory: SignalRHubConnectionFactory(),
        localStore: localStore,
        keyValueStore: UserDefaultsKeyValueStore(),
        connectivity: NetworkPathConnectivity()
    )
)
```

The app target then (all in `AppModel`, `RootView` and `ShellBanners`; app-shell.md has the
details):

1. **Launch.** `AppModel.start()`, called once from `didFinishLaunching`, subscribes to the
   streams below and calls `await environment.launch()`.
2. **Route on the session.** `environment.session.states()` drives the gate: loading, sign-in,
   bootstrap error with Retry (`retryBootstrap()`), configuration missing, password change,
   onboarding notice, primer, main tabs.
3. **Scene phase.** `await environment.setForeground(phase != .background)` on every change,
   including the initial phase. `.inactive` (Control Center, the app switcher) keeps realtime up.
4. **Push token.** `PushRegistrationCoordinator` calls
   `environment.push.register(token:preferences:)` with the FCM token and
   `environment.settings.currentSettings.notifications` when the session becomes `.signedIn`
   (and after an account switch) and on every token from `messaging(_:didReceiveRegistrationToken:)`,
   but never while signed out or while notification permission is denied or not yet asked.
   Preference changes re-register inside the data layer; sign-out unregisters inside the data
   layer. The app never calls `unregister()` itself.
5. **Foreground pushes.** `userNotificationCenter(_:willPresent:)` hides a chat push only when
   `environment.alerts.shouldPresentForegroundPush(conversationId:)` returns false.
6. **In-app banners** from `environment.alerts.alerts()`, on the tabs only.
7. **Connection banner** from `environment.realtimeStatus.banner()`. Its Retry calls `retryNow()`.
8. **Notification actions.** Reply goes through `messages.send` (or `threads.reply` for a thread
   root), Mark as read through `messages.markRead`; both only while signed in.
9. **Feature screens** read the environment with `@Environment(\.dataEnvironment)` (defined in
   this package behind `#if canImport(SwiftUI)`); `RootView` injects it. Previews use
   `.fakeDataEnvironment()` from WaiveraTestSupport.
10. **Fake environment (DEBUG only).** `LaunchOptions` reads
    `FakeDataEnvironment.scenario(fromArguments:)`, the only parser of `-WaiveraFakeServer` and
    `-WaiveraFakeScenario` (`demo` by default, `empty`, `failing`, `slow`, `signedOut` or
    `passwordChange`), and `CompositionRoot` then uses
    `FakeDataEnvironment.make(scenario, webBaseURL:).environment`. UI tests pass these launch
    arguments. `WaiveraTestSupport` is linked into the app target and every
    `import WaiveraTestSupport` is inside `#if DEBUG`. SwiftPM cannot link a package for one
    configuration only, so the code is still linked into Release builds, where nothing
    references it and dead-code stripping removes it.

`project.yml` lists `WaiveraData`, `WaiveraDataPersistence`, `WaiveraRealtimeSignalR` and
`WaiveraTestSupport` as app target dependencies.

## Fake composition

- `FakeDataEnvironment.make(_:clock:connectsRealtimeOnStart:webBaseURL:)` returns two things:
  - every fake, so tests can steer them;
  - `environment`, the `DataEnvironment` to hand to screens.
- **Clocks.** Tests pass `ManualClock`, which only moves on `advance(by:)`. The app uses
  `DemoClock`, which runs in real time starting from `DemoData.now`.
- **`DemoData.make()`** is built from the `WaiveraFixtures` payloads plus `DemoPayloads`, run
  through the production mappers. "Today" is 2026-11-01 in America/Chicago, the day DST ends.
  It includes:
  - in chat: unread 1:1, channel and group conversations, an archived read-only channel, a
    bot with a ticket card, a thread (9330), reactions, an attachment, a rich-text message, a
    system message, a call log (records 9370 and 9371) and a failed send with Retry;
  - in the calendar: today's all-day event, a shift across the repeated hour, a pending
    invitation, a meeting with a join link, time off, a holiday, a birthday and a five-year
    anniversary;
  - activity, bookmarks, the directory and the own profile.
- **Steering the fakes.**
  - `FakeControls(failure:latency:)` sets a failure or a latency, on one fake or on all of
    them through `setControls`.
  - `FakeChatRepository.setSendOutcome(.deliver | .fail(error) | .hold)` decides what sends
    do. `.hold` keeps them pending until `confirmPending()`.
  - `receive(_:)` delivers an incoming message, `setTyping` sets typing indicators, and
    `setReactionsAvailable(false)` makes reactions unavailable.
  - `FakeChatAlertsRepository.emit(_:)` shows an in-app banner. Its
    `shouldPresentForegroundPush` follows the live rule over the fake chat's presence and the
    fake hub; `activeConversationIds` forces a conversation to count as live.
  - Every fake records its calls in `calls` (a `CallLog`).
- **`FakeRealtimeClient`** is a scripted hub:
  - `connect()` and `drop(attempt:)` change the connection state.
  - `emit(_:)` delivers an event now; `play([ScriptedEvent])` delivers events on the clock.
  - Sends echo the client id back, as sprout_api does.
  - It is also usable with the live `ChatEngine` in tests.

## Gaps each repository works around

| Repository | Gap | Workaround |
| --- | --- | --- |
| `ChatEngine` (reactions) | G-01 | Hub-only and optimistic, with rollback; throws `.realtimeUnavailable` when disconnected |
| `LiveSessionRepository` | G-02 | The API client reads the enveloped login |
| all (decoding) | G-03 | `WaiveraJSON` matches keys case-insensitively and accepts enums as integers or strings |
| `LiveBookmarksRepository` | G-04 | When `/api/chat/bookmarks` fails, walks each conversation's bookmarked search with 4 workers. If that fails too, shows the original error. `usedFallback` is exposed |
| `ChatEngine` (inbox) | G-05 | Authors resolved from participants; a blank preview is filled from the detail endpoint; `lastMessage` merges never drop richer fields |
| `ChatEngine` (timeline) | G-06 | Page size fixed at 50; stops when a page is short or the cursor does not move |
| `LiveChatAlertsRepository`, `ChatEngine` | G-09 | Alerts come from `ReceiveChatAttention` only, gated by preferences and presence |
| `ChatEngine` (calls) | G-10 | Only Initiated, Active and Rejoined count as live |
| `ChatMapper` | G-11 | Deleted messages lose their content and reactions everywhere; the screen shows its own placeholder |
| all (errors) | G-12 | Every error shape maps to `WaiveraError`; server text is never shown |
| `ChatEngine` (inbox) | G-13 | Both `/all` flags are sent explicitly |
| `ChatEngine` (detail merge) | G-14 | The detail endpoint's unread count is ignored |
| `LiveAttachmentsRepository` | G-15 | Downloads send the auth header; 423 maps to `.attachmentBlocked`; a 40 MB LRU cache coalesces requests for the same file |
| `LivePushRegistrationRepository` | G-08 | The fingerprint skips duplicate registrations; preferences are client-owned and re-sent on change |

## Not done in the data layer

- Opening a conversation deep-linked to an older message: the message-context endpoint is not
  used. The timeline opens at the newest page, so the screen has to handle a target message
  that is not loaded.
- Read receipts (`ReceiveReadReceipt`) are decoded but not stored, because 03 §12 does not
  render them.
- `GET /api/chat/conversation/{id}/bookmarks` is not used. The global list and its fallback
  cover the bookmarks screen.
- Mark as read from a notification action, for a conversation whose timeline was never loaded,
  sends `MarkAsRead` but no read-through: `markRead(conversationId:)` takes no message id, although
  the push carries one. A `markRead(conversationId:throughMessageId:)` would close this.
- Call log grouping by `callRecordId` (03 §16) is left to the chat feature. The data layer
  exposes `isCallLog` and `callRecordId`.

## Platform notes

The following compile only on Apple platforms, so the Linux test run skips them:

- `KeychainTokenStore` (Security)
- `SwiftDataLocalStore` (SwiftData)
- `NetworkPathConnectivity` (Network)
- `EnvironmentValues.dataEnvironment` and WaiveraTestSupport's `View.fakeDataEnvironment` (SwiftUI)

`WaiveraRealtimeSignalR` compiles on Linux but has not run against a live hub. Everything else
runs on Linux with `swift test`:

- `WaiveraAPI`: 61 tests
- `WaiveraRealtime`: 35 tests
- `WaiveraData`: 127 tests
- `WaiveraTestSupport`: 21 tests
