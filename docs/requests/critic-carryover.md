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
| AF-06 Offline cold start skips the password gate | Fixed (was marked not applicable; disputed by the iOS review as IF-10) | iOS now opens offline from the last successful bootstrap of the same Firebase user and keeps retrying the login with capped backoff, so the gap AF-06 describes became possible and is closed: a bootstrap that answers with a password change or onboarding removes the cached bootstrap, and only a gate-free login saves one. `CriticFixSessionTests` "AF-06: a password change the server asked for is not skipped by a later offline launch", "IF-10: offline at a cold start, the last bootstrap opens the cached app and retries", "IF-10: offline at a cold start with nothing cached shows the bootstrap failure". |
| AF-07 Inline reply fails during cold bootstrap | Fixed | Reply and Mark as read wait up to 10 s for a settled session (`settledSignedInData`) and keep the notification when that fails. `AppModelCarryoverTests` `aReplyThatColdLaunchedTheAppWaitsForTheSession`. |
| AF-08 Mark read never rolls back | Fixed | `markRead` throws and restores the unread count; the list clears its optimistic read and its Retry calls the repository by conversation id. "AF-08: a failed mark-as-read restores the unread count and throws"; `ChatListMarkReadTests`. |
| AF-09 New conversation from the hub shows 0 unread | Not applicable | A message for a conversation the inbox has not seen triggers a full inbox refresh, which carries the server's unread counts. |
| AF-10 Edit keeps the stale preview | Fixed | `ChatEngine.edit` updates the inbox preview at once. "AF-10: an edit updates the inbox preview without waiting for the hub". |
| AF-11 Group opened during the rejoin is never joined | Fixed | `LiveRealtimeClient.rejoinGroups` loops until every attended group is joined. `LiveRealtimeClientTests` `aGroupOpenedDuringTheRejoinIsJoined`. |
| AF-12 Thread replies suppressed by the main view | Fixed | Presence is kept per surface (iOS review IF-02): a thread reply is hidden only while its own thread is on screen, a root message only while its conversation's main timeline is, and a thread being open no longer makes its conversation count as read. `PresentationAndResponseTests` `aThreadReplyIsShownEvenWhileItsConversationIsOnScreen`; `CriticFixNotificationTests` "IF-02: …"; `CriticFixChatTests` "IF-02: …". It takes effect for pushes once the server sends `threadRootMessageId` (`sprout-api.md` §8). |
| AF-13 No receive haptic while visible | Fixed, now effective | The first claim was not effective: the design system mapped `.messageReceivedWhileVisible` to no haptic (iOS review IF-09). It now plays the light selection tick, as on Android and in AGENTS.md, in conversations and in threads. `ConversationModelTests` `someoneElsesMessageArrivingOnScreenPlaysTheReceiveCue`, `ThreadModelTests` "IF-09: someone else's reply arriving in the open thread plays the receive cue", `HapticsTests`. |
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
| AS-08 Chat content unencrypted at rest | Product decision, backup closed | Protection stays at "until first unlock" so a push can refresh the cache on a locked phone; raising it is left to the product owner. What the iOS review added (IS-04) is fixed: the cache now lives in `Library/Caches/WaiveraCache` (never in iCloud or computer backups), the folder is also marked excluded from backup and given `completeUntilFirstUserAuthentication` on every launch, the old Application Support store is deleted, and sign-out deletes the SQLite files (including `-wal` and `-shm`) instead of only the rows. macOS only; not yet compiled. |
| AS-09 Chats in app switcher snapshots | Fixed (was partial, iOS review IS-05) | The first fix was an overlay on the root view, so sheets, full-screen covers, the image preview, the share sheet and Safari stayed in the snapshot. `PrivacyCoverController` now shows the cover in its own window at `.alert + 1` when a scene is about to resign active, and removes it when the scene is active again. macOS only; not yet compiled, no UI test yet. |
| AS-10 Shared attachment survives sign-out | Fixed | `AttachmentFiles.removeAll()` runs on sign-out. `MessageRulesTests` `sharedCopiesAreRemovedWhenTheSessionEnds`. |
| AS-11 Path-trusting channels endpoint still declared | Not applicable | The iOS API client never declared `get-myChannels`. |

## Corrections after the iOS review

The iOS functional and security reviews (`reviews/ios-functional.md`, `reviews/ios-security.md`)
re-checked the claims above. The rows for AF-06, AF-12, AF-13, AS-08 and AS-09 were corrected
in place. One claim was not in a row:

| Claim | Review result | Now |
| --- | --- | --- |
| Push registration retries on the next activation | Not effective in the live wiring (IF-06): the coordinator retries only when the register closure throws, and the live closure never threw because the repository swallowed its last error. | Fixed. `PushRegistrationRepository.registerAndWait` throws the final error and stores no fingerprint, and the app's coordinator closure uses it. `CriticFixSessionTests` "IF-06: registration that keeps failing throws and stores no fingerprint", "IF-06: the coordinator over the live repository retries on the next activation". |
