# Requests for `sprout_api`

Gaps that only the API can close, raised by the Android and iOS feature requests. Sections 1 to 7
come from the Android list (`waivera-android/docs/requests/sprout-api.md`) and apply to iOS the
same way; iOS raised 1, 2 and 3 independently (`today.md` §3 and §5, `chat-list.md` §6). Sections 8
to 11 are iOS additions. The client works without each one (the workaround is named), so none of
these blocks the native build. Evidence was read from the `sprout_api` source; paths are relative
to that repo. Nothing here changes client code.

On iOS the client names differ from Android's: the activity pager is `ActivityController`, the
ticket parser is `TicketUpdate` in `WaiveraData`, and the time-off balance is read in
`ProfileMapper`.

## 1. Activity unread total

From `today.md` §3.

- **Evidence.** `Controllers/Chat/ChatController.cs` `GET recent-activity` returns
  `List<ChatActivityResponse>` for one page (`page`, `pageSize` clamped to 1..100) with a per-row
  `Read` flag. There is no total, no unread count and no has-more flag.
- **Ask.** Add an unread total for the signed-in user, either as a wrapper
  (`{ items, unreadCount, hasMore }`) or a `GET recent-activity/unread-count` endpoint.
- **Client today.** Today loads up to 5 pages while the oldest loaded page still has an unread
  row, and shows "N+" when it stops at that cap. Once the count exists, core adds
  `ActivityRepository.observeUnreadCount()` and the pager goes away.

## 2. Pending invitations outside a date range

From `today.md` §8.

- **Evidence.** `Controllers/Calendar/CalendarEventController.cs` only offers range queries
  (`GetAllEvent?startTime&endTime`, `upcoming/Events-by-date`), `next-upcoming-events/{userId}`
  (the next two events) and `GetEventbyId/{id}`. None filters by the caller's invitation status.
- **Ask.** `GET api/CalendarEvent/pending-invitations` (or an `inviteStatus=pending` filter on
  `GetAllEvent` without a range) returning the same event DTO.
- **Client today.** Needs you lists pending invitations from the 14-day range Today already
  observes; an invitation further out does not appear there.

## 3. Conversation sort fallbacks

From `chat-list.md` §2.

- **Evidence.** `dto/Response/ChatResponeDto/UnifiedConversationResponse.cs` and
  `dto/Response/ConversationResponse.cs` carry `LastReadAt`, `UnreadCount`, `LastMessage`,
  `ActiveMeeting` and `OngoingCall`. They have no `LastActivityAt`, `ModifiedDate` or
  `CreateDate`, which spec 02 uses as the sort fallbacks.
- **Ask.** Add `lastActivityAt` (or `createDate` and `modifiedDate`) to both conversation shapes.
- **Client today.** `Conversation.activityAt` uses the last message time, then the live call
  start, then the meeting start. The list breaks ties by id, newest first.

## 4. Ticket bot messages: event type and status fields

From `today.md` §6 and spec 03 §15.

- **Evidence.**
  - Event types: `Services/Tickets/TicketService.cs` sends bot DMs through
    `ChatBotService.SendDirectMessageAsync` with these system event types:
    - `ticket.created` (line 124);
    - `ticket.comment` or `comment.mention` (around line 2370);
    - `ticket.{activity}`, such as `ticket.assigned` and `ticket.status` (line 2450).
  - No code path sends `ticket.update`, yet spec 03 and the Expo reference
    (`message-row.tsx:127`) render a ticket card only for `systemEventType === 'ticket.update'`.
  - Payload keys:
    - `ticket.created` sends `ticketId`, `title`, `type`, `createdBy`, `priority`,
      `createdAt`, `dueDate`, `createdDate`, `dueDateLabel` and `url`.
    - Activity messages send `ticketId`, `ticketInternalId`, `title`, `activity`, `detail` and
      `url`.
    - None of them sends a status or an assignee as separate fields.
- **Ask.**
  - Confirm the event type clients should treat as a ticket card. Either the server sends
    `ticket.update`, or clients match the `ticket.` prefix (and decide about `comment.mention`
    carrying a `ticketId`).
  - Add `status` and `assignee` to the payload if the cards should show them.
- **Client today.**
  - Core parses `ticket.update` only (`TicketUpdate.from`), which matches the spec and the
    reference app. On today's server that means no message is parsed as a ticket card, and those
    messages render as ordinary bot text.
  - Today's ticket row shows the ticket number and title when a payload parses, and otherwise
    falls back to "Ticket update".
  - Changing the matched type is a behaviour change from the reference app, so it waits for the
    decision above.

## 5. Separate time-off summary

From `feature-profile.md` §5.

- **Evidence.** `dto/Response/EmployeeTimeOffResponseDto.cs` repeats the balance on every request
  row: `AllocatedLeaveCount`, `RemainingLeaveCount`, `UsedLeavePercentage`, `RemainingLeaveDays`,
  `UsedLeaveDays`, the hour fields and the vacation and sick splits. There is no separate summary
  object, so a person with no requests has no balance.
- **Ask.** A summary shape (for example `{ balance, requests }`) or a balance endpoint.
- **Client today.** Core reads the balance from the first row (`TimeOffSummary.balance`) and
  prefers the server's `UsedLeavePercentage`.

## 6. Per-conversation mute

From the `chat-list.md` contract notes (spec 11, drift 56).

- **Evidence.** No chat controller, model or DTO has a mute flag. The only "mute" endpoints are
  video host controls (`Controllers/VideoController.cs` `host/mute`).
- **Ask.** Only if product wants muting: a participant-level `isMuted` with a toggle endpoint, and
  push suppression on the server.
- **Client today.** The list shows no muted indicator.

## 7. Read positions for receipts (only if receipts are wanted)

From `conversation.md` §4.

- **Evidence.**
  - The hub broadcasts `ReceiveReadReceipt(conversationId, userId, at)`, sent from
    `Controllers/Chat/ChatController.cs` lines 1348 and 1749.
  - The conversation DTOs only carry the caller's own `LastReadAt`. Nothing returns other
    participants' read positions for a cold start.
- **Ask.** If "Seen by" is wanted, return each participant's last-read message id (or time) with
  the conversation or messages.
- **Client today.** No receipts. The Expo reference never shows them either (spec 05 §6).

## 8. Thread root id in chat push data (iOS addition)

From the critic carry-over AF-12 (`critic-carryover.md`).

- **Evidence.** `Services/MobilePushNotificationService.cs` `BuildFcmChatMessage` sends `type`,
  `conversationId`, `messageId` and `url` in `data`. `ChatPush` has no thread field, although
  `Services/Chat/ChatAttentionService.cs` knows `message.ThreadRootMessageId` when it builds the
  attention item.
- **Ask.** Add `threadRootMessageId` to the push `data` (and the Expo payload) when the message
  is a thread reply, and a `url` of `/chats/{conversationId}/thread/{rootId}` for it (the path
  the native deep links already parse).
- **Client today.** `ChatPush.isThreadReply` reads `threadRootMessageId` when present. A reply is
  then never hidden because its conversation is on screen, and a tap opens the thread. Until the
  field is sent every reply is treated as a conversation message, so a reply that arrives while
  the person is in the conversation (but not the thread) is suppressed in the foreground.

## 9. Notification category by meaning (iOS addition)

From `feature-profile-settings.md` §4 and `NotificationCategory.swift`.

- **Evidence.**
  - `BuildFcmChatMessage` sends `aps.category = "CHAT_MESSAGE"` for every chat push, so a
    direct message, a mention and group chatter look the same to the device.
  - `dto/Request/MobilePushRegistrationRequest.cs` has `ChatMessagesEnabled`, `MentionsEnabled`,
    `ReactionsEnabled` and `ActiveCallsEnabled`, and nothing for schedule reminders, schedule
    changes or a digest.
- **Ask.**
  - Send the meaning as the APNs category (`messages`, `mentions`, `schedule_reminders`,
    `schedule_changes`, `digest`), keeping `CHAT_MESSAGE` working for the Expo app.
  - Add `ScheduleRemindersEnabled`, `ScheduleChangesEnabled` and `DigestEnabled` to the
    registration request, honoured when sending.
- **Client today.** Every chat push is classified as `messages`. Settings offers Messages
  (mentions and active calls) and Group activity (reactions) only; the schedule and digest
  switches are not shown.

## 10. Device registrations of a previous user (iOS addition)

From the critic carry-over AF-05 and AS-02.

- **Evidence.**
  - `Services/MobilePushRegistrationService.cs` looks a registration up by token and removes the
    same user's older registration for the device id. Another user's registration for the same
    device id is kept.
  - `Services/MobilePushNotificationService.cs` prunes a registration when FCM answers
    `UNREGISTERED` (line 266) or Expo answers `DeviceNotRegistered` (line 309).
- **Ask.** When a device id registers for a user, deactivate every other user's registration for
  that device id. A sign-out whose `unregister` call failed (offline) then stops delivering the
  previous person's chats as soon as the next person signs in.
- **Client today.** Sign-out calls `unregister`, then deletes the FCM token. If deleting fails it
  keeps a pending flag and retries at launch and on becoming active, so the old token is
  invalidated and the server prunes it at the next send. While both calls fail, the device can
  still receive the previous person's alerts in the background (iOS has no service extension yet
  to drop them).

## 11. FCM provider for native builds (iOS addition, already supported)

- **Evidence.** `MobilePushRegistrationRequest.Provider` defaults to `"expo"`, and
  `MobilePushProviders` has `Expo` and `Fcm`; the send path splits on it and builds an APNs
  alert with `mutable-content` for iOS FCM registrations.
- **Ask.** None beyond keeping `"fcm"` accepted. The iOS client sends `provider: "fcm"` and
  `platform: "ios"` (`MobilePushDTOs.swift`).

## Checked and not a gap

`MeetingHandoff` `relatedChatConversationId`:

- `dto/Request/VideoDtoObjects.cs` declares `RelatedChatConversationId` as `int?`.
- The Android `Long` therefore matches the API. The string in spec 02 describes the web lobby's
  own state, not the API.

Message context endpoint:

- `Controllers/Chat/ChatController.cs` line 861 serves
  `GET api/chat/{conversationId}/messages/context/{messageId}`, which `conversation.md` §1 asked
  for. iOS calls it through `MessagesRepository.loadAround(conversationId:messageId:)`.
