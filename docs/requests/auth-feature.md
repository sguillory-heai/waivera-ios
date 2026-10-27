# Requests from `AuthFeature`

Changes outside `Packages/Features/Sources/AuthFeature/` that the auth and onboarding screens
need. Each one is small. The feature works without them; each note says what is missing until it
lands. Android asked for the same things in `waivera-android/docs/requests/feature-auth.md`.

## 1. Data layer: password reset (`WaiveraAPI`, `WaiveraData`, `WaiveraTestSupport`)

"Forgot password?" (an open question in PLAN.md; Android ships it) needs Firebase's reset email:
`POST identitytoolkit accounts:sendOobCode` with `{ requestType: "PASSWORD_RESET", email }`.

- `FirebaseAuthClient.sendPasswordReset(email:)`; map `EMAIL_NOT_FOUND` to
  `.auth(.invalidCredentials)` as sign-in does (the screen shows "sent" for it, so it never
  reveals whether an account exists).
- `SessionRepository.sendPasswordReset(email:) async throws`, plus the fake (record the call,
  honour a failure switch).

AuthFeature already codes against it through `PasswordResetSending`
(`Model/PasswordResetSending.swift`): `PasswordResetAdapter.sender(for:)` returns the session when
it conforms. Once the method exists, either add `extension LiveSessionRepository:
PasswordResetSending {}` and the same for `FakeSessionRepository`, or replace the adapter with a
direct call. Until then the link is hidden on the sign-in screen (previews and snapshots show it
through a fixture).

## 2. App gate: keep the current gate while the session re-runs the bootstrap (`App/`)

`AppModel.sessionGate` maps `.bootstrapping` to `.signIn` (after the sign-in screen was shown) or
`.loading`. Three gate actions re-run the bootstrap, so each one throws the person off the screen
they are on:

- **Bootstrap failed → Try again**: the screen flips to sign-in or the loader and back. Its busy
  state and the "a retry failed" haptic are lost.
- **Onboarding → I've finished, check again**: the screen is rebuilt, so "Your account still
  needs setup" never shows.
- **Required password change → success**: the sign-in screen flashes before the tabs.

Smallest fix: when `.bootstrapping` follows `.bootstrapFailed`, `.onboardingRequired` or
`.passwordChangeRequired`, keep that gate until the next state arrives (remember the last gate in
`AppModel`, like `hasShownSignIn`). The feature models already handle `.bootstrapping` as "still
checking".

## 3. Data layer: a voluntary password change must not re-bootstrap through `.bootstrapping`

`LiveSessionRepository.changePassword` ends with `bootstrap()`, which publishes `.bootstrapping`.
From Settings (state `.signedIn`) that drops the app out of the tabs to the loader or sign-in
screen and loses the navigation stacks. Only re-run the bootstrap when the state is
`.passwordChangeRequired`; when signed in, confirm and stay signed in (or refresh the user
without publishing `.bootstrapping`).

Also make it resumable: if Firebase accepted the new password but `confirm-password-change`
failed (offline), a retry re-authenticates with the old password, which Firebase now rejects, and
the screen says "That isn't your current password". Remember (in memory, per uid) that the
Firebase step succeeded and retry only the confirm call.

## 4. Route: voluntary password change (`WaiveraRouting`, `App/`, `SettingsFeature`)

`PasswordChangeView(onDone:)` is the voluntary flow (no sign-out, calls `onDone` after the saved
confirmation has been shown). It needs:

- `AppRoute.changePassword`, deep link `waivera://settings/account/password`, a `RouteCatalog`
  entry `settings-change-password` (so the ScreenshotTour visits it), and in
  `RouteDestinationView`: `PasswordChangeView(onDone: { model.pop() })`;
- a "Change password" row in `AccountSettingsView` (owned by SettingsFeature), for example an
  `onChangePassword` closure next to `onSignOut`.

Land it after request 3, or the change drops the person out of the tabs.

## 5. Design system: `WaiveraTextField` focus and reveal (`WaiveraDesign`)

- The reveal button swaps `SecureField` for `TextField`, which drops focus and the keyboard
  mid-typing. Keep both fields in a `ZStack` and toggle their opacity and hit testing (moving focus
  to the visible one), or keep the `SecureField` and overlay a read-only reveal.
- Auth applies `.focused`, `.submitLabel` and `.onSubmit` from outside the component. That works
  through the environment and focus scope, but an explicit `focus: FocusState<Field?>.Binding`
  parameter, and the accessibility identifier on the inner field, would make it certain.

## 6. Build and CI (`project.yml`, `.github/workflows/ios.yml`)

Done in this branch, for the integrator to keep while merging the feature branches:

- `project.yml`: `WaiveraSnapshotTests` depends on `Features/AuthFeature` (for
  `AuthSnapshotTests`), and the scheme runs `Features/AuthFeatureTests`.

Not done (CI is not this feature's to change): a Linux step for the feature tests. `swift test
--package-path Packages/Features` fails on Linux because the other feature targets import SwiftUI
unguarded; this works today and stays fast:

```bash
swift build --package-path Packages/Features --product FeaturesPackageTests
swift test --package-path Packages/Features --skip-build
```

It keeps working as long as every feature target with a test target wraps its SwiftUI files in
`#if canImport(UIKit)`, as AuthFeature does.
