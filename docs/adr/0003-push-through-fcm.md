# 0003: Deliver pushes through FCM over APNs as grouped alerts

Status: Accepted (2026-10-27)

## Context

The Expo app registers Expo push tokens and sprout_api relays through Expo's push service.
Native apps cannot receive Expo tokens. sprout_api already sends some pushes through FCM HTTP v1,
and the Android app uses FCM too.

## Decision

- The app uses Firebase Messaging over APNs and registers its FCM token at
  `POST /api/mobile-push/register` with `provider: "fcm"` and `platform: "ios"` (sprout_api PR #881).
- sprout_api sends iOS chat pushes as APNs alerts: title and body, `thread-id` `chat-{conversationId}`
  so iOS groups them per conversation, category `CHAT_MESSAGE` for reply and mark-read actions,
  `mutable-content: 1`, and sound only when the user enabled it. `type`, `conversationId`,
  `messageId` and `url` ride alongside `aps` for routing.
- A Notification Service Extension will turn chat alerts into communication notifications
  (sender avatar, Focus breakthrough for mentions). Until it exists, alerts show as plain text.
- `TestSupport/Push/chat-message.apns` mirrors the payload so `xcrun simctl push` exercises routing.

## Consequences

- Real pushes need the Apple Developer account, an APNs key in Firebase and a signed build; the
  Simulator covers payload handling until then.
- New push kinds need a sprout_api change and a category or route here in the same ticket.
