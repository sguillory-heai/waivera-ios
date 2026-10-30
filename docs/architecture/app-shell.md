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

While the session re-runs the bootstrap from `bootstrapFailed`, `onboardingRequired` or
`passwordChangeRequired`, the gate stays on that screen until the next state arrives
(`AppModel.gateHeld(whileRebootstrappingFrom:)`), so Try again, Check again and the forced
password change keep their busy state instead of flashing the loader or sign-in.

While signed in and a scene is not active, `PrivacyCoverController` (owned by `AppDelegate`)
shows `PrivacyCover` in its own window at `.alert + 1`, above sheets, full-screen covers, the
share sheet and Safari, so the app switcher snapshot shows no messages. On sign-out the app removes every delivered
notification and the attachment files saved for sharing.

The primer shows once per install (`PrimerSeenStore`). "Turn on notifications" requests full
authorization (system prompt); "Not now" requests provisional (quiet) delivery, so no prompt
appears and nothing is lost. Settings → Notifications shows the system status
(`SystemNotificationStatus`) with "Turn on", "Turn on alerts" or "Open Settings".

## Tabs and stacks

Bottom tabs, in order: **Today** (`sun.max`), **Chat** (`bubble.left.and.bubble.right`),
**Schedule** (`calendar`). Each tab has its own `NavigationStack` bound to
`NavigationState.path(for:)`. The system `TabView` keeps each tab's state, but its bar is hidden
and the shell draws `WaiveraTabBar` (the approved Android navigation bar: the sliding violet pill,
the icon pop and the Chat unread count in `navBadge`). As on Android the bar shows on tab roots
only; a pushed screen gets the full height. This departs from spec §10 (keep the system tab bar)
because the owner approved the Android bar.

Every tab root draws its own hero bar (`HeroTopBar`, no system navigation bar) with the signed-in
avatar. Tapping it opens the account menu, `AccountMenuSheet` (Android `AccountMenuSheet`): the
person (opens Profile), People, Bookmarks and Settings. Picking a row closes the sheet and pushes
onto the selected tab, so back returns to the tab the menu was opened on. The shell passes
`AppModel.presentAccountMenu` to every root (`onOpenAccount` / `onAccount`), and also provides
it, with the avatar photo it loads for the signed-in person, through
`\.waiveraAccountMenu` (`AccountMenuEntry`), which any `HeroTopBar` without an account of its own
falls back to. Chat's hero bar also carries the "+" for a new chat.

Feature navigation closures push onto the selected tab (`AppModel.push`). Deep links and push
taps replace the target tab's stack, so a push-opened chat backs out to the inbox.

The status bar should be light over the plum hero. SwiftUI has no per-screen status bar style
without a navigation bar, so this needs a UIKit hosting controller override; it is listed in
`reviews/ios-macos-compile-risks.md` for the macOS pass.

## Routes

`AppRoute` values carry ids only; screens load their own data. Ids from links and pushes are
validated (`Identifier.positiveInt`, `Identifier.opaque`).

| Route | Arguments | Deep link | Entry view | Module |
| --- | --- | --- | --- | --- |
| Today root | — | `waivera://today` | `TodayView(onOpenConversation: (conversationID, targetMessageID?), onOpenThread: (rootMessageID, conversationID?, targetMessageID?), onOpenEvent: (eventID), onOpenSchedule: (), onOpenActivity: (), onOpenAccount: ()?)` — "Send wishes" on a celebration card opens its chat through `onOpenConversation` | TodayFeature |
| `.activity` | — | `waivera://activity` | `ActivityView(onOpenConversation:onOpenThread:)` (same closure shapes as Today) | TodayFeature |
| Chat root | — | `waivera://chats` | `ConversationListView(onOpenConversation: (conversationID), onOpenPerson: (userID), onNewChat: (), accountName: String?, accountLabel: String?, onAccount: ()?)` — `onNewChat` is the hero bar's "+" | ChatFeature |
| sheet `.newChat` | — | `waivera://chats/new` | `NewChatView(onOpenConversation: (conversationID), onDismiss: ())` | ChatFeature |
| `.conversation` | `conversationID: Int`, `targetMessageID: Int?` | `waivera://chats/{id}[?messageId=]` | `ConversationView(conversationID:targetMessageID:onOpenThread: (rootMessageID, targetMessageID?), onOpenPerson: (userID), onOpenMembers: (conversationID)?)` — a group's "N members" line calls `onOpenMembers` | ChatFeature |
| `.groupMembers` | `conversationID: Int` | `waivera://chats/{id}/members` | `GroupMembersView(channelID:onOpenPerson: (userID), onOpenConversation: (conversationID))` — a full pushed screen; back keeps its search | ChatFeature |
| `.thread` | `rootMessageID: Int`, `conversationID: Int?`, `targetMessageID: Int?` | `waivera://chats/thread/{rootId}[?conversationId=&messageId=]` or `waivera://chats/{id}/thread/{rootId}[?messageId=]` | `ThreadView(rootMessageID:conversationID:targetMessageID:onOpenPerson:)` | ChatFeature |
| Schedule root | — | `waivera://schedule`, `waivera://calendar` | `ScheduleView(onOpenEvent: (eventID), onOpenConversation: (conversationID)?, onOpenAccount: ()?)` — without `onOpenConversation` the celebration cards hide "Send wishes" | ScheduleFeature |
| `.calendarEvent` | `eventID: String` | `waivera://calendar/{eventId}`, `waivera://calendar?eventId=` | `CalendarEventView(eventID:onOpenConversation: (conversationID))` | ScheduleFeature |
| `.profile` | — | `waivera://profile` | `ProfileView(onOpenOrganization: (), onOpenSettings: ())` | ProfileFeature |
| `.organization` | — | `waivera://profile/organization` | `OrganizationView()` | ProfileFeature |
| `.people` | — | `waivera://people` | `PeopleView(onOpenPerson: (userID))` | ProfileFeature |
| `.person` | `userID: String` | `waivera://people/{userId}` | `PersonView(userID:onOpenConversation: (conversationID))` — Message and Send wishes open the chat | ProfileFeature |
| `.bookmarks` | — | `waivera://bookmarks` | `BookmarksView(onOpenMessage: (conversationID, messageID, threadRootMessageID?))` — a thread bookmark opens the thread by its **root** id | ProfileFeature |
| `.settings` | — | `waivera://settings`, `waivera://settings/account` (older links) | `SettingsView(onOpenNotifications: (), onOpenAppearance: (), onOpenChangePassword: ()?, onSignOut: ())` — Preferences, Security and Account on one screen, as on Android; Sign out asks on the shared confirmation sheet before calling `onSignOut` | SettingsFeature |
| `.notificationSettings` | — | `waivera://settings/notifications` | `NotificationSettingsView(systemStatus: SystemNotificationStatus, onRequestPermission: (), onOpenSystemSettings: ())` | SettingsFeature |
| `.appearanceSettings` | — | `waivera://settings/appearance` | `AppearanceSettingsView()` | SettingsFeature |
| `.changePassword` | — | `waivera://settings/password`, `waivera://settings/account/password` (older links) | `PasswordChangeView(onDone: ())` — the voluntary change; `onDone` runs after the saved confirmation | AuthFeature |

`waivera://` links for profile, people, bookmarks and settings open on the selected tab. Anything
unrecognised or invalid leaves the stacks as they are (`DeepLink.destination` returns `nil`) and
the tabs show "That link can't be opened in Waivera." in the shared snackbar above the tab bar
(`AppModel.unopenableLink`, Android UI2-22).

Links opened from inside the app (message text, attachments, event details) go through
`RootView`'s `OpenURLAction`, which asks `LinkPolicy.decide(_:)`: a `waivera://` link for a
known route navigates (an unknown path is blocked), an `http` or `https` link with a host opens in
the browser, and every other scheme (`javascript:`, `file:`, `tel:` and so on) is blocked. A
blocked `waivera://` link gets the same snackbar; other schemes are dropped quietly. Chat's own open-in-app and
open-externally actions check `SafeLinks.isAllowed` too.

Keep the entry view initializer signatures, or update this table, `TabRootView` and
`RouteDestinationView` in the same change. Data comes from the data
layer, not through these initializers: read `@Environment(\.dataEnvironment) private var data`
(a `DataEnvironment?`, `nil` only in an unconfigured build, which never shows a feature screen)
and build the feature model from the repositories it needs. Previews use
`.fakeDataEnvironment(.demo | .empty | .failing | .slow)` from WaiveraTestSupport inside `#if DEBUG`
(example in `ConversationView.swift`).

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
- **Firebase**: only `FirebaseMessaging` (and `FirebaseCore` to configure it), only in the app
  target (`App/Sources/Push`), configured from `.xcconfig` values; skipped entirely when they are
  empty. Swizzling is off; the app passes the APNs token to FCM itself. Firebase 13 deprecates
  `messaging(_:didReceiveRegistrationToken:)` in favour of installation-ID registration
  (`FirebaseMessagingInstallationIdEnabled`), which sprout_api cannot target yet: it sends to FCM
  registration tokens. The app stays on token registration until the API moves.
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
- **Unopenable links**: the "That link can't be opened in Waivera." snackbar (see Deep links),
  above the tab bar, announced to VoiceOver and closed after `FeedbackTiming`.

Not sent: `ConversationsRepository.failedSends()` replays the ids of conversations whose newest
outbox send failed (fed by `ChatEngine`'s outbox, cleared on sign-out). The Chat inbox row and
Today's Needs you both read it, so a failed send shows "Not sent" in both until it goes out or is
discarded.

The account avatar: `MainTabView` loads the signed-in person's photo through
`AvatarRepository.avatar(userId:)` once per user and shares it with every hero bar and the account
menu; the initials tile shows until it arrives or when there is none.

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
| `-WaiveraRoute <name>` | open a `RouteCatalog` entry on launch: a gate (`loading`, `sign-in`, `bootstrap-failed`, `configuration-missing`, `password-change`, `onboarding-required`, `notification-primer`) or a route name from the table above (`today`, `activity`, `chat`, `chat-new`, `conversation`, `conversation-target`, `thread`, `schedule`, `calendar-event`, `profile`, `organization`, `people`, `person`, `bookmarks`, `settings`, `settings-notifications`, `settings-appearance`, `settings-change-password`, `group-members`) |
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
  accessibility XXXL. State entries (`<route>-empty`, `<route>-failing`, `<route>-slow`,
  from `RouteCatalog.stateScenarios` over `stateRoutes`) relaunch with that fake scenario, so the
  tour also shows each screen's empty, error and slow-loading state. Attachments are named `<route>__<device>-<variant>` and kept on success.
  Each screen gets `performAccessibilityAudit()`; every issue is attached as
  `<route>__<device>-<variant>__accessibility` and recorded as a failure without stopping the tour.
- `WaiveraSnapshotTests` snapshots the shared components at iPhone SE width in light, dark and
  accessibility XXXL. A missing reference is recorded (and fails once); commit the PNGs from the
  CI `snapshots` artifact into `WaiveraSnapshotTests/__Snapshots__/`.
- CI exports every attachment to PNG (`xcrun xcresulttool export attachments`) and uploads the
  `screenshots` artifact.
