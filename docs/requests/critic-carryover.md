# Android critic findings, checked on iOS

The Android functional and security reviews (`reviews/android-functional.md`,
`reviews/android-security.md` in the native-rebuild notes) found these problems in the Android
build. Each one was checked against the iOS code. Where the same gap existed it was fixed with a
test; the test named here fails without the fix. Linux-tested packages ran in docker; tests in
`WaiveraTests` need macOS and have not been run yet.

## Functional (AF)

| Finding | iOS status | What iOS does, and the test |
| --- | --- | --- |
| AF-01 Directory from a super-admin endpoint | Not applicable | `LivePeopleRepository` already reads `get-username-list`. |
| AF-02 Echo fallback drops a second identical send | Fixed | The text-and-time fallback runs only for an echo without a `clientMessageId`. `RequestsAndCarryoverTests` "AF-02: a repeated echo with a confirmed client id never drops another queued message". |
| AF-03 `loadAround` leaves a hole before the tail | Fixed | `ChatEngine.loadAround` fills forward until the context page meets the loaded rows, and does not merge when the gap is too long. "AF-03: loading around an old message fills forward to the loaded rows, with no hole", "Load around: a hole too long to close is not merged". |
| AF-04 Involuntary sign-out skips cleanup | Fixed | Every path into signed out goes through one teardown in `LiveSessionRepository`, and caches written for another user are never shown. `SessionTests` "AF-04: a rejected bootstrap wipes the caches even though the session never started". |
| AF-05 Unregister failure leaves pushes arriving | Fixed, one limit | Sign-out deletes the FCM token (`PushTokenSource.invalidate()`), keeps a pending flag and retries at launch and on activation; foreground presentation is suppressed while signed out, and delivered notifications are removed. `PushRegistrationCoordinatorTests` `signOutDeletesTheTokenSoAKeptRegistrationGoesNowhere`, `aFailedTokenDeletionIsRetriedOnActivationAndAtTheNextLaunch`, `signingInDropsAPendingDeletion`; `PresentationAndResponseTests` `nothingIsShownWhileSignedOut`; `AppModelCarryoverTests` `signOutDeletesThePushToken`, `nothingIsPresentedWhileSignedOut`. Limit: iOS shows a background alert push without running app code, so while both the unregister and the token deletion fail, alerts can still arrive. Closing that needs a Notification Service Extension or the server change in `sprout-api.md` §10. |
| AF-06 Offline cold start skips the password gate | Not applicable | iOS has no offline cached session; every launch bootstraps against the API before showing content. |
| AF-07 Inline reply fails during cold bootstrap | Fixed | Reply and Mark as read wait up to 10 s for a settled session (`settledSignedInData`) and keep the notification when that fails. `AppModelCarryoverTests` `aReplyThatColdLaunchedTheAppWaitsForTheSession`. |
| AF-08 Mark read never rolls back | Fixed | `markRead` throws and restores the unread count; the list clears its optimistic read and its Retry calls the repository by conversation id. "AF-08: a failed mark-as-read restores the unread count and throws"; `ChatListMarkReadTests`. |
| AF-09 New conversation from the hub shows 0 unread | Not applicable | A message for a conversation the inbox has not seen triggers a full inbox refresh, which carries the server's unread counts. |
| AF-10 Edit keeps the stale preview | Fixed | `ChatEngine.edit` updates the inbox preview at once. "AF-10: an edit updates the inbox preview without waiting for the hub". |
| AF-11 Group opened during the rejoin is never joined | Fixed | `LiveRealtimeClient.rejoinGroups` loops until every attended group is joined. `LiveRealtimeClientTests` `aGroupOpenedDuringTheRejoinIsJoined`. |
| AF-12 Thread replies suppressed by the main view | Fixed in policy | A thread reply is never suppressed because its conversation is on screen. `PresentationAndResponseTests` `aThreadReplyIsShownEvenWhileItsConversationIsOnScreen`. It takes effect once the server sends `threadRootMessageId` (`sprout-api.md` §8). |
| AF-13 No receive haptic while visible | Fixed | The conversation plays `.messageReceivedWhileVisible` for someone else's live message, not for backfill. `ConversationModelTests` `someoneElsesMessageArrivingOnScreenPlaysTheReceiveCue`. The design system currently maps that cue to no haptic. |
| AF-14 Invitation answer cancelled when the screen closes | Not applicable | The commit runs in an unstructured `Task` the model does not cancel when the view disappears. |
| AF-15 KDoc says push-off unregisters | Not applicable | iOS really unregisters when push is turned off, so the comment and the code agree. |

## Security (AS)

| Finding | iOS status | What iOS does, and the test |
| --- | --- | --- |
| AS-01 Involuntary sign-out leaves data and push | Fixed | Same fix as AF-04, plus the push steps of AF-05. |
| AS-02 Notifications shown while signed out | Fixed, one limit | Same as AF-05: foreground suppression, delivered notifications removed, token deleted with retry. Background alerts have the same limit. |
| AS-03 Outbox not bound to the account | Fixed | Each outbox entry records its author, and entries from another account are dropped, never sent. "AS-03: queued messages from another account are dropped, never sent". |
| AS-04 App-wide link handler opens any scheme | Fixed | `RootView` installs an `OpenURLAction` that asks `LinkPolicy.decide(_:)`; chat's open actions check `SafeLinks.isAllowed`. `LinkPolicyTests` `appLinksNavigateInsideTheApp`, `webLinksGoToTheBrowser`, `everyOtherSchemeIsBlocked`. |
| AS-05 Cleartext allowed, `http://` bases accepted | Fixed | App Transport Security blocks cleartext by default, and `WaiveraConfiguration.load` accepts only `https` bases (an `http` web base is dropped). `ConfigurationTests` `httpsValuesLoad` and the rejection cases. |
| AS-06 Inline reply from the lock screen | Not applicable | Reply and Mark as read are registered with `.authenticationRequired`. |
| AS-07 Firebase refresh token in plain storage | Not applicable | iOS keeps tokens in the Keychain, and Firebase Auth runs over REST in `WaiveraAPI`, so no SDK store is involved. |
| AS-08 Chat content unencrypted at rest | Product decision | The cache relies on iOS default data protection (encrypted while the device is locked after first unlock). Raising it to complete protection would stop background refresh; the choice is left to the product owner and is recorded here. |
| AS-09 Chats in app switcher snapshots | Fixed | `PrivacyCover` covers the content while signed in and the scene is not active. Compiles on macOS only. |
| AS-10 Shared attachment survives sign-out | Fixed | `AttachmentFiles.removeAll()` runs on sign-out. `MessageRulesTests` `sharedCopiesAreRemovedWhenTheSessionEnds`. |
| AS-11 Path-trusting channels endpoint still declared | Not applicable | The iOS API client never declared `get-myChannels`. |
