---
name: verify-ios-ui
description: Verify a new or changed SwiftUI screen on the simulator before calling it done. Use after any UI, animation, haptics, or navigation change.
---

Verify the changed UI as a user would, then record evidence.

1. List the affected screens and the states that apply: loading, empty, populated, long content, error, offline/reconnecting, disabled, selected.
2. Build and launch on the simulator with XcodeBuildMCP, launched with `-WaiveraFakeServer` (optionally `-WaiveraFakeScenario empty|failing|slow|signedOut|passwordChange`), which runs the `WaiveraTestSupport` fakes (never shared dev data).
3. For each screen and state, capture settled screenshots (wait for animations to finish) in:
   - light and dark mode
   - iPhone SE size and a current Pro Max size
   - default and largest accessibility Dynamic Type size
4. Interact for real: tap every control, swipe back, pull to refresh, send a message, toggle settings. Confirm exactly one state change per action, no layout jumps, no clipped text.
5. Turn on Reduce Motion and confirm animations fall back to fades or none.
6. Run an accessibility audit (`XCUIApplication().performAccessibilityAudit()` in the UI test for the screen) and fix findings.
7. If push or realtime is involved, send a payload with `xcrun simctl push booted com.waivera.waivera <file>.apns` while the app is foregrounded, backgrounded, and killed. Confirm the banner, badge, and deep link.
8. Update or add snapshot tests for the screen in the states above.
9. Score the result 1 to 10 for professional polish against `AGENTS.md` design rules. Below 9.5, fix the findings and repeat the affected steps.

Report: screens checked, states covered, screenshots path, what you could not check and why. Never claim a check you did not run.
