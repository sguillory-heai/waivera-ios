# Architecture decision records

One short file per decision that would be expensive to reverse. Read the relevant
records before changing architecture, and add a new record (never rewrite an
accepted one) when a decision changes.

Format: `NNNN-title.md` with Status, Context, Decision, Consequences.

| ADR | Decision | Status |
| --- | --- | --- |
| [0001](0001-native-rebuild.md) | Rebuild natively instead of staying cross-platform | Accepted |
| [0002](0002-app-architecture.md) | Local packages, XcodeGen and a local source of truth | Accepted |
| [0003](0003-push-through-fcm.md) | Deliver pushes through FCM over APNs as grouped alerts | Accepted |
| [0004](0004-today-first-tabs-and-typed-routes.md) | Today-first tabs, typed routes and a Foundation routing package | Accepted |
