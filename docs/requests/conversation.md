# Requests from the conversation and thread screens (`ChatFeature`)

Gaps the conversation and thread screens hit in modules they do not own. Each one has a local
workaround in `Packages/Features/Sources/ChatFeature/{Conversation,Thread,Message}`, which should
be removed once the request lands.

## 1. Load the page around a message (`sprout_api` + `WaiveraData`)

A deep link or notification can target a message far above the newest page (03 §9). There is no
message-context endpoint and `MessageRepository` has no way to load the page that contains a given
message.

- Request: add `GET /api/chat/{conversationId}/messages/{messageId}/context` (or a `aroundMessageId`
  query on the messages endpoint) and `loadAround(conversationId:messageId:)` on `MessageRepository`.
- Workaround: `ConversationModel.highlightTargetIfNeeded()` loads older pages until the target is
  present, at most 8 pages (`maxHighlightPages`), then gives up quietly. The thread screen already
  has every reply, so it needs nothing.

## 2. Report an older-page failure on its own (`WaiveraData`)

When `ChatEngine.loadOlder` fails it sets the whole timeline's `phase` to `.failed`, the same signal
as a failed refresh. The screen cannot tell "the top page did not load" from "the list is stale".

- Request: keep `phase` as it was and expose the failure separately, for example
  `MessageTimeline.olderPageError: WaiveraError?`, cleared on the next successful page.
- Workaround: the screen shows the stale banner over the rows it has. The "loading older" row
  stays at the top, so scrolling back up retries.

## 3. Link the conversation tests and snapshots (`project.yml`, app owner)

- `WaiveraSnapshotTests` dependencies: add `package: Features, product: ChatFeature` and
  `package: WaiveraTestSupport, product: WaiveraTestSupport`. Until then
  `WaiveraSnapshotTests/ConversationSnapshotTests.swift` is guarded by
  `#if canImport(ChatFeature)` and compiles to nothing. It uses `@testable import ChatFeature`,
  so it only runs in Debug builds, where packages are built with testability.
- Scheme `Waivera` test targets: add `package: Features/ChatConversationTests`. Until then the
  tests run with `swift test --package-path Packages/Features --filter ChatConversationTests`.
- The first run records 45 references (15 states, 3 variants each) at iPhone SE size into
  `WaiveraSnapshotTests/__Snapshots__/ConversationSnapshotTests/`. Commit them from the CI
  `snapshots` artifact.

## 4. Screenshot tour coverage (`WaiveraUITests`, app owner)

`RouteCatalog` has `conversation`, `conversation-target` and `thread`, which show the demo
conversation 7 and thread 9330. The read-only bot conversation is not in the tour.

- Request: add `("conversation-bot", "waivera://chats/90")` so the read-only notice and the ticket
  card get the accessibility audit.
- The other states (loading, empty, error, reconnecting, typing, send error, editing, live call,
  and the thread's loading, empty, error and read-only states) are covered by
  `ConversationSnapshotTests` through `ChatPreviewData`.

## 5. Notes for reviewers (no change requested)

- **Linux checks.** `Packages/Features` cannot build on Linux, because the other features' views
  are not guarded by `#if canImport(UIKit)`. The conversation logic and tests were checked with a
  scratch package that links only `ChatFeature` without `ChatScreens.swift`. Every SwiftUI file in
  `Conversation/`, `Thread/` and `Message/` is guarded, so a Linux build of the package only needs
  the other features guarded the same way.
- **Day separators.** The timeline inserts a day separator before the first row of each day in
  the employee's time zone, to match the Android app.
- **Read receipts.** Not rendered, as 03 §12 says; the data layer drops `readReceipt` hub events
  (`ChatEngine+Realtime`). Showing "Seen" later needs a per-conversation read state from
  `WaiveraData`.
- **Plurals.** Plural copy uses `key.one` and `key.other` entries in `Conversation.strings`, picked
  by `ConversationStrings.plural(_:count:)`, because Foundation on Linux crashes reading
  `.stringsdict`. Languages that need more plural forms will need a `.stringsdict` once the Linux
  check is no longer required.
- **Strings.** All copy is in the feature's own `Conversation.strings` table. The shared
  `Localizable.strings` was not changed.
