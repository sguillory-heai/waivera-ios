---
name: sync-api-contract
description: Mirror a sprout_api DTO, endpoint, or SignalR hub event change into the WaiveraAPI, WaiveraRealtime and WaiveraData packages. Use when the backend contract changes or a decode fails.
---

1. Find the source of truth in `sprout_api`: the controller action, the request/response DTO under `dto/`, or the hub method under `Hubs/`. Note nullability, enum values, and date formats.
2. Update the matching Swift `Codable` type in `Packages/WaiveraAPI` (or the event model in `WaiveraRealtime`). Keep property names aligned; use `CodingKeys` only when Swift naming requires it. If screens need the field, carry it through the mapper in `Packages/WaiveraData/Sources/WaiveraData/Mapping` (`ChatMapper`, `CalendarMapper`, `ProfileMapper`), which is the only way DTOs become models.
3. Map C# nullable fields to Swift optionals. Map enums with an `.unknown` fallback case.
4. Dates: decode as UTC instants. If the endpoint omits the zone suffix, use the shared lenient UTC decoder, not a local-time parse.
5. Add or update a fixture JSON in `Packages/WaiveraFixtures/Sources/WaiveraFixtures/Fixtures` (list it in `Packages/WaiveraFixtures/FIXTURES.md`), captured from the real response shape, and a decode test using it. Push payload fixtures are also copied into `Packages/WaiveraNotifications/Tests/WaiveraNotificationsTests/Fixtures`. If demo mode should show it, wire it into `DemoData` in `Packages/WaiveraTestSupport`.
6. Run `swift test` for `Packages/WaiveraAPI`, `Packages/WaiveraRealtime`, `Packages/WaiveraData` and `Packages/WaiveraTestSupport` (all run on Linux).
7. If the Android repo consumes the same contract, note the change in the PR so the Android DTO is updated under the same ticket ID.
