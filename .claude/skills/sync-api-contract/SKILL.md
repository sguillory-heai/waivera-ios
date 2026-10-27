---
name: sync-api-contract
description: Mirror a sprout_api DTO, endpoint, or SignalR hub event change into the WaiveraAPI or WaiveraRealtime package. Use when the backend contract changes or a decode fails.
---

1. Find the source of truth in `sprout_api`: the controller action, the request/response DTO under `dto/`, or the hub method under `Hubs/`. Note nullability, enum values, and date formats.
2. Update the matching Swift `Codable` type in `Packages/WaiveraAPI` (or the event model in `WaiveraRealtime`). Keep property names aligned; use `CodingKeys` only when Swift naming requires it.
3. Map C# nullable fields to Swift optionals. Map enums with an `.unknown` fallback case.
4. Dates: decode as UTC instants. If the endpoint omits the zone suffix, use the shared lenient UTC decoder, not a local-time parse.
5. Add or update a fixture JSON in `TestSupport/Fixtures` captured from the real response shape, and a decode test using it.
6. Run `swift test --package-path Packages/WaiveraAPI`.
7. If the Android repo consumes the same contract, note the change in the PR so the Android DTO is updated under the same ticket ID.
