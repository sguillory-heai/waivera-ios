# App shell

How the app target wires features together: the auth gate, the tabs, typed routes, deep links,
push notifications and the composition root. Feature agents fill in the entry views listed here
without touching `App/`. If a screen needs a new route or a new navigation closure, change this
file, `WaiveraRouting` and `App/Sources/Views/RouteDestinationView.swift` together.

## Modules

| Module | Kind | Owns |
| --- | --- | --- |
| `Packages/WaiveraRouting` | Foundation, Linux-tested | `AppTab`, `AppRoute`, `AppSheet`, `Destination`, `DeepLink` parser, `NavigationState` reducer, `RouteCatalog` |
| `Packages/WaiveraNotifications` (`WaiveraNotifications`) | Foundation, Linux-tested | push payload parsing, categories by meaning, foreground presentation options, tap routing, permission primer policy, `PushRegistrationCoordinator` (when to hand the token to the data layer), `PushTokenSource` |
| `Packages/WaiveraNotifications` (`WaiveraNotificationsLive`) | iOS only | `UNUserNotificationCenter` delegate, category registration, authorization, clearing delivered notifications |
| `Packages/WaiveraDesign` | tokens Linux-tested, SwiftUI iOS only | colours, type, spacing, radii, motion, haptics, shared components |
| `Packages/Features` | iOS only | one library per feature (below) |
| `App/` | app target | `AppModel`, composition root (`CompositionRoot`, `DataLayerBridge`), views that host the features, app-wide banners, Firebase Messaging adapter |

Features depend on `WaiveraDesign`, `WaiveraData` and `WaiveraAPI` (plus `WaiveraTestSupport`
for previews and tests, imported only inside `#if DEBUG`), never on each other. Only
`RouteDestinationView` and `TabRootView` in `App/` import more than one feature.

## Launch and the auth gate

`AppDelegate` builds `AppModel` from `CompositionRoot.makeEnvironment` and sets the notification
center delegate before launch finishes (so a cold-start tap is delivered). `AppModel.start()` (called
from `didFinishLaunching`) subscribes to the data layer's streams and calls
`DataEnvironment.launch()` once. `RootView` injects the data layer into the SwiftUI environment
(`\.dataEnvironment`) and renders `AppModel.gate`, which maps `SessionState`:

| Session state | Screen | Entry view (module) |
| --- | --- | --- |
| `loading`, or `bootstrapping` on a cold start with a stored session | full-screen "Loading Waivera…" | `LoadingStateView` (WaiveraDesign) |
| `signedOut`, or `bootstrapping` after the sign-in screen was shown | sign-in (shows its own "Connecting" state from `SessionRepository`) | `SignInView()` (AuthFeature) |
| `bootstrapFailed(error)` | `error.userMessage` + Retry (`retryBootstrap`) + Sign out | `BootstrapFailedView(message:onRetry:onSignOut:)` (AuthFeature) |
| `configurationMissing` (no `.xcconfig` values) | explanation, nothing else runs | `ConfigurationMissingView()` (AuthFeature) |
| `passwordChangeRequired` | explanation + Sign out | `PasswordChangeRequiredView(onSignOut:)` (AuthFeature) |
| `onboardingRequired` | explanation + Sign out | `OnboardingRequiredView(onSignOut:)` (AuthFeature) |
| `signedIn`, permission not asked, primer not seen | notification primer | `NotificationPrimerView(onEnable:onNotNow:)` (AuthFeature) |
| `signedIn` | tabs | `MainTabView` (App) |

The primer shows once per install (`PrimerSeenStore`). "Turn on notifications" requests full
authorization (system prompt); "Not now" requests provisional (quiet) delivery, so no prompt
appears and nothing is lost. Settings → Notifications shows the system status
(`SystemNotificationStatus`) with "Turn on", "Turn on alerts" or "Open Settings".

## Tabs and stacks

Bottom tabs, in order: **Today** (`sun.max`), **Chat** (`bubble.left.and.bubble.right`),
**Schedule** (`calendar`). Each tab has its own `NavigationStack` bound to
`NavigationState.path(for:)`. Today and Chat show the avatar menu (`AvatarMenuButton`) in the
leading top bar slot with Profile, People, Bookmarks and Settings; those push onto the selected
tab. Feature navigation closures push onto the selected tab (`AppModel.push`). Deep links and
push taps replace the target tab's stack, so a push-opened chat backs out to the inbox.

iOS 26: the tab bar adopts Liquid Glass from the SDK; `tabBarMinimizeBehavior(.onScrollDown)` is
applied behind `#available(iOS 26, *)`.

## Routes

`AppRoute` values carry ids only; screens load their own data. Ids from links and pushes are
validated (`Identifier.positiveInt`, `Identifier.opaque`).

| Route | Arguments | Deep link | Entry view | Module |
| --- | --- | --- | --- | --- |
| Today root | — | `waivera://today` | `TodayView(onOpenConversation: (conversationID, targetMessageID?), onOpenThread: (rootMessageID, conversationID?, targetMessageID?), onOpenEvent: (eventID), onOpenSchedule: (), onOpenActivity: ())` | TodayFeature |
| `.activity` | — | `waivera://activity` | `ActivityView(onOpenConversation:onOpenThread:)` (same closure shapes as Today) | TodayFeature |
| Chat root | — | `waivera://chats` | `ConversationListView(onOpenConversation: (conversationID), onNewChat: ())` | ChatFeature |
| sheet `.newChat` | — | `waivera://chats/new` | `NewChatView(onOpenConversation: (conversationID), onDismiss: ())` | ChatFeature |
| `.conversation` | `conversationID: Int`, `targetMessageID: Int?` | `waivera://chats/{id}[?messageId=]` | `ConversationView(conversationID:targetMessageID:onOpenThread: (rootMessageID, targetMessageID?), onOpenPerson: (userID))` | ChatFeature |
| `.thread` | `rootMessageID: Int`, `conversationID: Int?`, `targetMessageID: Int?` | `waivera://chats/thread/{rootId}[?conversationId=&messageId=]` or `waivera://chats/{id}/thread/{rootId}[?messageId=]` | `ThreadView(rootMessageID:conversationID:targetMessageID:onOpenPerson:)` | ChatFeature |
| Schedule root | — | `waivera://schedule`, `waivera://calendar` | `ScheduleView(onOpenEvent: (eventID))` | ScheduleFeature |
| `.calendarEvent` | `eventID: String` | `waivera://calendar/{eventId}`, `waivera://calendar?eventId=` | `CalendarEventView(eventID:onOpenConversation: (conversationID))` | ScheduleFeature |
| `.profile` | — | `waivera://profile` | `ProfileView(onOpenOrganization: (), onOpenSettings: ())` | ProfileFeature |
| `.organization` | — | `waivera://profile/organization` | `OrganizationView()` | ProfileFeature |
| `.people` | — | `waivera://people` | `PeopleView(onOpenPerson: (userID))` | ProfileFeature |
| `.person` | `userID: String` | `waivera://people/{userId}` | `PersonView(userID:onOpenConversation: (conversationID))` | ProfileFeature |
| `.bookmarks` | — | `waivera://bookmarks` | `BookmarksView(onOpenMessage: (conversationID, messageID, threadRootMessageID?))` — a thread bookmark opens the thread by its **root** id | ProfileFeature |
| `.settings` | — | `waivera://settings` | `SettingsView(onOpenNotifications:onOpenAppearance:onOpenAccount:)` | SettingsFeature |
| `.notificationSettings` | — | `waivera://settings/notifications` | `NotificationSettingsView(systemStatus: SystemNotificationStatus, onRequestPermission: (), onOpenSystemSettings: ())` | SettingsFeature |
| `.appearanceSettings` | — | `waivera://settings/appearance` | `AppearanceSettingsView()` | SettingsFeature |
| `.accountSettings` | — | `waivera://settings/account` | `AccountSettingsView(onSignOut: ())` — shows the shared confirmation sheet before calling `onSignOut` | SettingsFeature |

`waivera://` links for profile, people, bookmarks and settings open on the selected tab. Anything
unrecognised or invalid is ignored (`DeepLink.destination` returns `nil`).

Entry views are placeholders (`FeaturePlaceholder`) until each feature lands; keep the initializer
signatures, or update this table and the app router in the same change. Data comes from the data
layer, not through these initializers: read `@Environment(\.dataEnvironment) private var data`
(a `DataEnvironment?`, `nil` only in an unconfigured build, which never shows a feature screen)
and build the feature model from the repositories it needs. Previews use
`.fakeDataEnvironment(.demo | .empty | .failing | .slow)` from WaiveraTestSupport inside `#if DEBUG`
(example in `ChatScreens.swift`).

## Push notifications

Payload → route (`PushPayloadParser`, `PushPayload.destination`):

| Payload | Route |
| --- | --- |
| `type: "chat"` with `conversationId` (+ `messageId`) | `.conversation(id, targetMessageID: messageId)` on Chat |
| `type: "chat"` with `threadRootMessageId` (not sent yet) | `.conversation` then `.thread` |
| `type: "chat"` with missing/zero/non-numeric `conversationId` | no navigation |
| legacy `NotificationType: "meeting"` | `.calendarEvent(CalenderEventId)`, else Schedule |
| legacy `NotificationType: "call"` | `.conversation(conversationId)`, else Chat |
| legacy `NotificationType: "Survey"` | Today (no survey screen) |
| any other `type` | Chat inbox |

- **Categories by meaning** (`NotificationCategories.all`): `messages`, `group_activity`,
  `schedule_reminders`, `schedule_changes`, `digest`, plus the server's current `CHAT_MESSAGE`.
  Chat categories carry **Reply** (text input) and **Mark as read**. Grouping uses the server's
  `thread-id` `chat-{conversationId}`; Mark read clears that thread's delivered notifications.
- **Foreground rule**: one source of truth, the data layer's
  `ChatAlertsRepository.shouldPresentForegroundPush(conversationId:)`, which hides a chat push only
  when the hub is connected **and** that conversation (or a thread in it) is open with the app in
  the foreground (`ChatPresence`, fed by `MessagesRepository.open/close`). `AppModel` passes its
  answer to `ForegroundPresentationPolicy`, which only turns it and the settings into options:
  otherwise a banner (list only when In-app banners is off; sound only when Sound is on). The
  router's visible route is not consulted. The icon badge is never set by a push.
- **Taps** (`NotificationTapRouter`): each response routes once (last 50 keys remembered); a tap
  before sign-in finishes is held and opened after authentication; leaving the app before
  signing in discards it.
- **Registration**: `PushRegistrationCoordinator` decides *when* the token goes to the data layer:
  after sign-in (and after an account switch), on every FCM token rotation, never while signed
  out or while permission is denied or not yet asked. It calls
  `PushRegistrationRepository.register(token:preferences:)` with
  `SettingsRepository.currentSettings.notifications`. The repository owns everything else: the
  400 ms debounce, the stored fingerprint (a repeat call does nothing), retries with backoff,
  re-registering when a notification switch changes, and the single unregister during
  `SessionRepository.signOut()` (before Firebase is cleared). The shell never unregisters.
- **Actions**: Reply sends through the outbox (`MessagesRepository.send`, or `ThreadsRepository.reply`
  when the push names a thread root); Mark as read calls `MessagesRepository.markRead` and clears
  the conversation's delivered notifications. Both are dropped unless the session is signed in.
- **Firebase**: only `FirebaseMessaging`, only in the app target (`App/Sources/Push`), configured
  from `.xcconfig` values; skipped entirely when they are empty. Swizzling is off; the app passes
  the APNs token to FCM itself.
- **Entitlement**: push delivery needs the `aps-environment` entitlement, which is not added yet
  (pending Apple Developer account access and approval). Until then `registerForRemoteNotifications`
  fails quietly and the simulator payloads below are the way to test.
- Simulator payloads for every type: `TestSupport/Push/*.apns`
  (`xcrun simctl push booted com.waivera.waivera TestSupport/Push/legacy-meeting.apns`).
  `SimulatorPayloadTests` checks each one routes as named.

## In-app banners

`ShellBanners` (App) sits over the tabs:

- **Connection**: `RealtimeStatusRepository.banner()`. Hidden while connected and during the first
  connect; `reconnecting` and `offline` show the design-system banner with Retry
  (`retryNow()`), pinned under the status bar.
- **Messages**: `ChatAlertsRepository.alerts()` (already filtered by the In-app banners switch and
  presence). Shown only on the tabs, never over a gate, for `FeedbackTiming.inAppBanner` (longer
  with VoiceOver, announced). Open routes like a push tap (`ChatDestination`, threads by root);
  Dismiss or a newer alert replaces it.

## Composition root and fake mode

`CompositionRoot.makeEnvironment` picks, in order:

1. **Fake server**: DEBUG builds launched with `-WaiveraFakeServer` and optionally
   `-WaiveraFakeScenario demo|empty|failing|slow|signedOut|passwordChange`.
   `FakeDataEnvironment.scenario(fromArguments:)` is the only parser of those arguments
   (`LaunchOptions.fakeScenario`). Data comes from `FakeDataEnvironment` (the demo user signs in
   with the hub connected); permission counts as granted so no system prompt appears; the primer
   flag lives in a throwaway defaults suite.
2. **Live**: `DataLayerBridge.makeLiveEnvironment` when the `.xcconfig` values are present
   (Keychain tokens, the SignalR hub, the SwiftData document cache, `UserDefaults` settings,
   `NWPathMonitor` connectivity) with the FCM token source.
3. **Unconfigured**: no data layer, the configuration-missing gate, no network, no push.

`AppEnvironment` is the seam: the `DataEnvironment` (or `nil`), the FCM token source, the
authorizer and the primer store. Scene phase goes to `DataEnvironment.setForeground` on every
change (`phase != .background`, so `.inactive` keeps the hub), including the initial phase.

## DEBUG launch arguments

| Argument | Effect |
| --- | --- |
| `-WaiveraFakeServer` | fake backend and hub (above) |
| `-WaiveraFakeScenario <name>` | with `-WaiveraFakeServer`: `demo` (default), `empty`, `failing`, `slow`, `signedOut`, `passwordChange` |
| `-WaiveraRoute <name>` | open a `RouteCatalog` entry on launch: a gate (`loading`, `sign-in`, `bootstrap-failed`, `configuration-missing`, `password-change`, `onboarding-required`, `notification-primer`) or a route name from the table above (`today`, `activity`, `chat`, `chat-new`, `conversation`, `conversation-target`, `thread`, `schedule`, `calendar-event`, `profile`, `organization`, `people`, `person`, `bookmarks`, `settings`, `settings-notifications`, `settings-appearance`, `settings-account`) |
| `-WaiveraAppearance light\|dark` | force the colour scheme |
| `-WaiveraDisableAnimations` | UIKit animations off, for fast settled screenshots |
| `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` | system: largest text size |

All are ignored in Release builds.

## Tests

- `WaiveraRouting`, `WaiveraNotifications` and `WaiveraDesignTokens` tests run on Linux
  (`swift test --package-path Packages/<Name>`).
- `WaiveraTests` (hosted in the app) tests `AppModel` over `FakeDataEnvironment`: the gate for
  each session state (including bootstrap failure with Retry and missing configuration), the
  primer, registration after sign-in with the stored preferences, denied permission, one
  unregister through the session's sign-out, held taps, Reply / thread reply / Mark read, the
  foreground rule through the data layer, settings-driven appearance, the message and
  connection banners, and launch routes. During integration these tests and the app's model and
  composition files were also compiled and run on Linux with stand-ins for UIKit and SwiftUI
  (default main-actor isolation, warnings as errors); that check is not part of CI.

## Screenshots and snapshots

- `WaiveraUITests/ScreenshotTour.swift` visits every `RouteCatalog` entry in light, dark and
  accessibility XXXL. Attachments are named `<route>__<device>-<variant>` and kept on success.
  Each screen gets `performAccessibilityAudit()`; every issue is attached as
  `<route>__<device>-<variant>__accessibility` and recorded as a failure without stopping the tour.
- `WaiveraSnapshotTests` snapshots the shared components at iPhone SE width in light, dark and
  accessibility XXXL. A missing reference is recorded (and fails once); commit the PNGs from the
  CI `snapshots` artifact into `WaiveraSnapshotTests/__Snapshots__/`.
- CI exports every attachment to PNG (`xcrun xcresulttool export attachments`) and uploads the
  `screenshots` artifact.
