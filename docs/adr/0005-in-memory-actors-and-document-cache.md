# 0005: In-memory actors own session state; SwiftData is a document cache

Status: Accepted (2026-10-27). Supersedes the "SwiftData is the source of truth for anything a
screen lists" line of [ADR 0002](0002-app-architecture.md); the rest of 0002 stands.

## Context

ADR 0002 planned SwiftData as the store every list screen reads. Building the data layer showed
three problems with that:

- Chat state changes from three sources at once: hub events, REST pages and optimistic sends
  from the outbox. Applying them through a shared `ModelContext` makes it hard to guarantee that
  one change is never seen half-applied, and every reconnect resync becomes a multi-row merge.
- A normalized SwiftData schema needs a migration whenever a DTO or model gains a field, and
  sprout_api changes often during the rebuild.
- SwiftData does not exist on Linux, where the logic is tested without macOS minutes.

## Decision

- During a signed-in session the source of truth is a set of in-memory actors in `WaiveraData`.
  `ChatEngine` owns the inbox, timelines, threads and the outbox; each other repository owns
  its own state. Each serializes its own changes, so a hub event, a REST page and an optimistic
  send cannot interleave half-applied.
- Screens observe replaying `AsyncStream`s of `Resource<Value>` (value, phase, last update).
- `LocalStore` persists one JSON document per `CacheKey` for an instant first frame and for
  pending sends. On device it is `SwiftDataLocalStore` (`WaiveraDataPersistence`, one row per
  document); tests, previews and the fake server use `InMemoryLocalStore`.
- The server stays authoritative: the next successful fetch replaces a cached document, a
  document that no longer decodes counts as a miss, and sign-out wipes the store.

## Consequences

- No schema migrations: a changed model only costs one cache miss after an update.
- The whole data layer, its fakes and the app shell's model are tested on Linux.
- Queries over cached data (search, filters) run in memory over the actor's state, not as
  SwiftData predicates. That is fine at the sizes one employee sees; revisit with a new ADR if
  a screen needs to page through more than fits in memory.
- Feature models must never read SwiftData directly; they go through the repository protocols.
