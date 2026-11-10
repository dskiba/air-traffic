# Contributing

Thanks for helping. Air Traffic stays small on purpose, so a few ground rules:

- **Simple first.** The smallest change that solves the problem. No new dependencies.
- **Logic goes in `AirTrafficCore`** (pure, tested); `AirTraffic` is the AppKit shell.
- **Nothing slow on the link path** (`AppDelegate.application(_:open:)` → `route` → `Browsers.open`).
- **Tests:** `swift test` must pass; add a test for any routing or URL-handling change.
- **UI changes:** attach a before/after screenshot of the window (not your whole screen).

## Develop

```sh
swift test            # core tests
./build.sh            # build/Air Traffic.app
./build.sh install    # copy to /Applications and launch
```

Send yourself a link without changing your default browser:

```sh
open -a "build/Air Traffic.app" "https://example.com/?utm_source=test"
```

## Adding a browser

Profiles: add the bundle id and its `~/Library/Application Support` folder to `Browsers.chromium`
or `Browsers.firefox`. Desktop-app handoff: add a mapping to `Links.nativeApp(for:)` with a test.
