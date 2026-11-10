# Air Traffic — agent notes

macOS 26+ link router (default-browser shim). Swift 6 + AppKit, zero dependencies. See README for features.

- Build: `./build.sh` (bundle in `build/`), tests: `swift test` (core only).
- Release: update CHANGELOG.md, then `git tag vX.Y.Z && git push --tags`; release.yml builds, zips and publishes.
- Keep routing logic in `AirTrafficCore` (pure, tested); the app target is a thin AppKit shell with
  `defaultIsolation(MainActor)`.
- Hot path = `AppDelegate.application(_:open:)` → `route()` → `Browsers.open`. No allocation-heavy work,
  no SwiftUI, no network there.
- Size budget: app bundle < 1 MB. No dependencies without a reason in numbers.

## Learnings

- Never take full-screen screenshots when verifying UI; capture only the app's window
  (`screencapture -o -l <windowID>`), the user's screen has private work on it.
- Name no type `Picker`/`Toggle`/etc. clashing with SwiftUI without qualifying (`SwiftUI.Picker`) in views.
- Pass linker flags via `-Xlinker` in `unsafeFlags` (swiftc is the linker driver).
- Never set `NSPanel.isFloatingPanel` after `level`: it silently resets the level to `.floating`.
- Check competitor claims (README comparison) against their docs before writing them.
- Never use `git stash` in a repo without commits; it fails and skips the rest of the chain.
