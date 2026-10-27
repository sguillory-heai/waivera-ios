# App shell

How the app target wires features together: the auth gate, the tabs, typed routes, deep links,
push notifications and the composition root. Feature agents fill in the entry views listed here
without touching `App/`. If a screen needs a new route or a new navigation closure, change this
file, `WaiveraRouting` and `App/Sources/Views/RouteDestinationView.swift` together.

## Modules

| Module | Kind | Owns |
| --- | --- | --- |
| `Packages/WaiveraRouting` | Foundation, Linux-tested | `AppTab`, `AppRoute`, `AppSheet`, `Destination`, `DeepLink` parser, `NavigationState` reducer, `RouteCatalog` |
| `Packages/WaiveraNotifications` (`WaiveraNotifications`) | Foundation, Linux-tested | push payload parsing, categories by meaning, foreground presentation rule, tap routing, permission primer policy, `PushRegistrationCoordinator`, `PushTokenSource` |
| `Packages/WaiveraNotifications` (`WaiveraNotificationsLive`) | iOS only | `UNUserNotificationCenter` delegate, category registration, authorization, clearing delivered notifications |
| `Packages/WaiveraDesign` | tokens Linux-tested, SwiftUI iOS only | colours, type, spacing, radii, motion, haptics, shared components |
| `Packages/Features` | iOS only | one library per feature (below) |
| `App/` | app target | `AppModel`, composition root, views that host the features, Firebase Messaging adapter |

Features depend on `WaiveraDesign` (and the core packages), never on each other. Only
`RouteDestinationView` and `TabRootView` in `App/` import more than one feature.

## Launch and the auth gate

`AppDelegate` builds `AppModel` from `CompositionRoot.makeEnvironment` and sets the notification
center delegate before launch finishes (so a cold-start tap is delivered). `RootView` renders
`AppModel.gate`:

| Session state | Screen | Entry view (module) |
| --- | --- | --- |
| loading | full-screen "Loading Waivera…" | `LoadingStateView` (WaiveraDesign) |
| signed out | sign-in | `SignInView()` (AuthFeature) |
| password change required | explanation + Sign out | `PasswordChangeRequiredView(onSignOut:)` (AuthFeature) |
| onboarding required | explanation + Sign out | `OnboardingRequiredView(onSignOut:)` (AuthFeature) |
| signed in, permission not asked, primer not seen | notification primer | `NotificationPrimerView(onEnable:onNotNow:)` (AuthFeature) |
| signed in | tabs | `MainTabView` (App) |

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
layer, injected the way `docs/architecture/data-layer.md` describes, not through these
initializers.

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
- **Foreground rule** (`ForegroundPresentationPolicy`): a chat push is hidden only when the hub
  is connected **and** that conversation is on screen. Otherwise it shows as a banner (list only
  when In-app banners is off; sound only when Sound is on). The icon badge is never set by a push.
- **Taps** (`NotificationTapRouter`): each response routes once (last 50 keys remembered); a tap
  before sign-in finishes is held and opened after authentication; leaving the app before
  signing in discards it.
- **Registration** (`PushRegistrationCoordinator`): registers after sign-in and on every FCM
  token rotation, re-registers after a preference change (debounced 400 ms in `AppModel`),
  retries a failed attempt on the next foreground, never registers while permission is denied or
  not yet asked, and unregisters **before** sign-out clears the session.
- **Firebase**: only `FirebaseMessaging`, only in the app target (`App/Sources/Push`), configured
  from `.xcconfig` values; skipped entirely when they are empty. Swizzling is off; the app passes
  the APNs token to FCM itself.
- **Entitlement**: push delivery needs the `aps-environment` entitlement, which is not added yet
  (pending Apple Developer account access and approval). Until then `registerForRemoteNotifications`
  fails quietly and the simulator payloads below are the way to test.
- Simulator payloads for every type: `TestSupport/Push/*.apns`
  (`xcrun simctl push booted com.waivera.waivera TestSupport/Push/legacy-meeting.apns`).
  `SimulatorPayloadTests` checks each one routes as named.

## Composition root and fake mode

`CompositionRoot.makeEnvironment` picks, in order:

1. **Fake server** — DEBUG builds launched with `-WaiveraFakeServer`. Shell gateways are fixed
   (signed in as the fixture user, hub connected, permission granted, no system prompt). When
   `WaiveraData` and `WaiveraTestSupport` are in the project, `DataLayerBridge.makeFakeEnvironment`
   supplies the fake-server repositories instead.
2. **Live** — `DataLayerBridge.makeLiveEnvironment` when `WaiveraData` is in the project and the
   `.xcconfig` values are present.
3. **Unconfigured** — sign-in screen, no network, no push.

`AppEnvironment` is the seam: session states, shell preferences (appearance, haptics, in-app
banners, sound, a push-registration fingerprint), hub connection, notification chat actions
(reply, mark read), push register/unregister closures, the FCM token source, the authorizer and
the primer store.

### Integration with the data layer (pending)

`DataLayerBridge.swift` compiles only when `WaiveraData` can be imported. To integrate:

1. Add `WaiveraData` (and, for DEBUG, `WaiveraTestSupport`) to `packages:` and the `Waivera`
   target's dependencies in `project.yml`.
2. Implement the two factory functions in `DataLayerBridge`: wrap `SessionRepository` in a
   `SessionGateway` (map its states to `ShellSession`; the user id is the backend id),
   `SettingsRepository` in a `PreferencesGateway`, the realtime client's connection state in
   `HubStatusGateway`, the outbox/read-through in `ChatActionsGateway`, and
   `PushRegistrationRepository.register(token:preferences:)` / `unregister()` in the push closures.
3. Inject the repositories feature screens need into the SwiftUI environment at `RootView`.

## DEBUG launch arguments

| Argument | Effect |
| --- | --- |
| `-WaiveraFakeServer` | fake backend and hub (above) |
| `-WaiveraRoute <name>` | open a `RouteCatalog` entry on launch: a gate (`loading`, `sign-in`, `password-change`, `onboarding-required`, `notification-primer`) or a route name from the table above (`today`, `activity`, `chat`, `chat-new`, `conversation`, `conversation-target`, `thread`, `schedule`, `calendar-event`, `profile`, `organization`, `people`, `person`, `bookmarks`, `settings`, `settings-notifications`, `settings-appearance`, `settings-account`) |
| `-WaiveraAppearance light\|dark` | force the colour scheme |
| `-WaiveraDisableAnimations` | UIKit animations off, for fast settled screenshots |
| `-UIPreferredContentSizeCategoryName UICTContentSizeCategoryAccessibilityXXXL` | system: largest text size |

All are ignored in Release builds.

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
