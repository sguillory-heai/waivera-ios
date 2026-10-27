# Chat list: requests to core, app and CI owners

The chat list feature (`ChatFeature/List`, `ChatFeature/NewChat`, `ChatListTests`) did not edit
these areas. Each item says what is needed and why.

## App and project

1. **Run `ChatListTests` in CI.** `Packages/Features/Package.swift` now declares the
   `ChatListTests` test target. Add it to the `Waivera` scheme's test targets in `project.yml`
   (or run `swift test --package-path Packages/Features` in CI) so it runs on macOS.
2. **Snapshot coverage for the list.** `WaiveraSnapshotTests` depends only on `WaiveraDesign`.
   Add `- package: Features, product: ChatFeature` to it so snapshot cases can render
   `ChatListContentView` and `NewChatContentView` with `ChatListPreviewData` (light, dark,
   accessibility5, iPhone SE width). Both views take `showsSkeletonImmediately: true` so the
   loading state can be snapshotted without waiting for the 300 ms gate.
3. **Screenshot tour state variants.** The tour cannot show the empty, error or reconnecting
   list. A scenario switch per stop (`FakeDataEnvironment.make(.empty / .failing)`) would cover
   spec 02's state list.
4. **Open a person from the list.** `ConversationListView(onOpenConversation:onNewChat:)` has no
   person closure, so View profile opens `waivera://people/{id}` through `openURL`. Either route
   that link in the app's `onOpenURL`, or add `onOpenPerson: (String) -> Void` to the entry view
   in `app-shell.md` (the list would switch to it).

## Data layer

5. **`DataEnvironment.clock`.** The list's relative times use `SystemClock()`. The fake
   environment's demo data sits at `DemoData.now`, so previews and the tour show "Now" or future
   times. Exposing the environment's clock lets features use the demo clock.
6. **Sort fallback timestamps.** `ChatEngine` orders by `lastMessage.createdAt ?? lastReadAt`.
   Spec 02 falls back to the conversation's modified and created dates for chats with no message
   and no read marker (for example a new channel). Those fields are not on `Conversation`.
7. **Mark-read result.** `MessageRepository.markRead` gives no result or error, so the list's
   optimistic mark-as-read cannot roll back on failure. It returns to the server value at the next
   inbox refresh. A thrown error or result would allow a visible retry.
8. **Realtime status types.** The `WaiveraRealtime` product is not a `Features` dependency, so the
   list reads only `isConnected` and `epoch` from `RealtimeStatusRepository.statuses()`. If more
   connection detail is wanted in the pill, re-export the needed types from `WaiveraData`.

## Spec

9. **Spec 02 §9 email title compaction.** The spec example compacts `operations.team@…` to
   "operations.tea…", but the Expo code it cites cuts the local part (to 15 characters plus "…")
   only when it is longer than 16. The list follows the code, as Android does
   (`operations.team & 1 other`). Update the spec example or confirm the intended rule.
