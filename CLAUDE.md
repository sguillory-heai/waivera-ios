@AGENTS.md

## Claude Code specifics

- Project skills live in `.claude/skills/`. Use `verify-ios-ui` before calling any UI work done, and `sync-api-contract` whenever a `sprout_api` DTO or hub event changes.
- Recommended third-party skills (install per developer, review before use): `swiftui-pro` (twostraws), `swift-concurrency` (AvdLee), `swift-testing-pro` (twostraws). They advise; this file and `AGENTS.md` win on conflicts.
- Simulator, Xcode, and hook steps need macOS: a Mac, a cloud Mac, or the GitHub Actions macOS runner. On Windows, run package logic and contract work only and say which checks were left for macOS.
- Use XcodeBuildMCP for build, test, simulator launch, screenshots, and UI interaction instead of hand-parsing `xcodebuild` output.
- Formatting and lint run automatically through hooks in `.claude/settings.json`. Do not disable or bypass them.
- For changes touching more than one feature module, plan first and list the modules you will touch.
- Before pushing, run `/code-review` on the diff and fix confirmed findings. Run `/security-review` when the change touches auth, Keychain, push payloads, or networking.
- Personal notes (simulator names, local API URL) go in `CLAUDE.local.md`, which is git-ignored.
