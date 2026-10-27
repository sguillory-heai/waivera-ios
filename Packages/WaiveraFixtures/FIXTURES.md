# Fixtures

Realistic sample payloads for both native test suites. Field names, casing, nullability and
enum spellings follow the C# DTOs and the serializer settings documented in
`../contract/rest.md` §0, `../contract/hub.md` §1 and `../contract/push.md`.
All data is fabricated (`@example.com`, "Alex Rivera", "Priya Raman", "Jordan Lee",
`usr_*` ids, `room_*`, example tokens). Nothing came from seed SQL.

## Conventions

* **`rest-*.json`** — the HTTP response body exactly as the server writes it, including the
  `ApiResponse<T>` envelope where the endpoint uses one and **omitting** keys whose value is
  null (`DefaultIgnoreCondition = WhenWritingNull`). Request-body samples are named
  `*-request-*.json`.
* **`hub-*.json`** — the SignalR invocation, because several events use positional arguments:
  `{ "target": "ReceiveReaction", "arguments": [7, 9312, "usr_jordan_lee", "👍", "added"] }`.
  Hub payloads keep explicit `null`s (the hub protocol does **not** ignore nulls) and encode
  `enum`s as **integers** (see `hub-conversation-created-channel.json`, where
  `channel.channelType` is `1` while REST sends `"TEAM"`).
* **`push-*.json`** — the FCM HTTP v1 request body the server sends
  (`push-chat-message-android.json`, `push-chat-message-ios.json`), the Expo relay batch
  (`push-chat-message-expo.json`), and the bare FCM data map for
  `onMessageReceived` tests (`push-chat-message-android-data.json`).
* **Timestamps** — chat and calendar instants are deliberately written **without a zone
  suffix** (`"2026-10-20T14:32:11.482913"`) because that is what the server emits; parse as
  UTC. Fields that really do carry `Z` (`readAt`, `timeOff[].startTime`, hub
  `ReceiveMessageDelete.deletedAt`) are written with it. See `../contract/dates.md` §3.
  Fractional-second digit counts vary on purpose — decoders must tolerate 0–7 digits.

## Edge-case variants

| Shape under test | Fixture |
| --- | --- |
| Conversation with no last message | `rest-chat-get-my-conversations-null-last-message.json` |
| Conversation with a live call | `rest-chat-get-my-conversations.json` (item 3) |
| Conversation with a scheduled meeting | `rest-chat-get-my-conversations-with-meeting.json` |
| Bot direct conversation | `rest-chat-get-my-conversations.json` (item 4) |
| Channel item, archived channel, `conversationId` key | `rest-chat-get-all.json` |
| `lastMessage.author` as the fat `MessageAuthorResponse` | `rest-chat-get-conversation.json` |
| Message with an attachment | `rest-chat-get-messages-pagination-with-attachment.json`, `hub-receive-message-attachment.json` |
| Deleted message | `rest-chat-get-messages-pagination-deleted.json` |
| Thread root + replies | `rest-chat-get-messages-pagination-reply.json`, `rest-chat-get-thread.json`, `hub-receive-message-reply.json` |
| Message with reactions | `rest-chat-get-messages-pagination-with-reaction.json` |
| Rich text (`contentFormat: 1`, parsed `messageDoc`) | `rest-chat-get-messages-pagination-richtext.json` |
| System / channel-event message | `rest-chat-get-messages-pagination-system-message.json` |
| Empty page | `rest-chat-get-messages-pagination-empty.json` |
| Reaction added / updated / removed | `hub-receive-reaction-*.json` |
| Read-all (`conversationId: 0`) | `hub-receive-chat-read-state-read-all.json` |
| `lastReadAt` null on a read receipt | `hub-receive-read-receipt-null.json` |
| Call ended | `hub-conversation-call-state-changed-end.json` |
| All-day + recurring calendar event, exclusive end date | `rest-calendar-get-all-event.json` |
| Preview disabled / sound off push | `push-chat-message-android-silent-no-preview.json`, `push-chat-message-ios-no-preview-no-sound.json` |
| Attachment-only push body | `push-chat-message-android-attachment-only.json` |
| Legacy participant-targeted pushes (PascalCase data keys) | `push-legacy-meeting.json`, `push-legacy-call.json`, `push-legacy-survey.json` |
| PascalCase 500 from `ExceptionMiddleware` | `rest-error-exception-middleware-500.json` |
| camelCase error envelopes | `rest-error-apiresponse-unauthorized.json`, `rest-error-controller-500.json` |
| Push registration rejection | `rest-mobile-push-register-error.json` |
