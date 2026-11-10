#!/bin/sh
# Builds "build/Air Traffic.app". `./build.sh install` also copies it to /Applications and launches it.
set -eu
cd "$(dirname "$0")"

# Universal binary: macOS 26 still runs on some Intel Macs.
ARCHS="--arch arm64 --arch x86_64"
swift build -c release --product AirTraffic $ARCHS
BIN="$(swift build -c release $ARCHS --show-bin-path)/AirTraffic"
APP="build/Air Traffic.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp "$BIN" "$APP/Contents/MacOS/AirTraffic"
strip -x "$APP/Contents/MacOS/AirTraffic"

# Icon Composer file (Resources/AppIcon.icon) → Assets.car, if present.
if [ -d Resources/AppIcon.icon ]; then
  xcrun actool Resources/AppIcon.icon --compile "$APP/Contents/Resources" \
    --platform macosx --minimum-deployment-target 26.0 --app-icon AppIcon \
    --output-partial-info-plist build/icon-info.plist >/dev/null
fi

codesign --force --options runtime --sign "${SIGN_ID:--}" "$APP"
du -sh "$APP"

if [ "${1:-}" = "install" ]; then
  osascript -e 'quit app "Air Traffic"' 2>/dev/null || true
  rm -rf "/Applications/Air Traffic.app"
  cp -R "$APP" /Applications/
  open "/Applications/Air Traffic.app"
fi
