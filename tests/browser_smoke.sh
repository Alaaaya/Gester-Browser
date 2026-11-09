#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$RUNNER_TEMP/browser-smoke"
mkdir -p "$WORK/Smoke.app"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
xcrun clang -target "$ARCH-apple-ios15.0-simulator" -isysroot "$SDK" -fobjc-arc -fblocks -g -O0 -I"$ROOT/src" -framework UIKit -framework Foundation -framework ImageIO "$ROOT/tests/browser_smoke.m" "$ROOT/src/ReadOnlyBrowserVC.m" -o "$WORK/Smoke.app/Smoke"
python3 - "$WORK/Smoke.app/Info.plist" <<'PY'
import plistlib,sys
plistlib.dump(dict(CFBundleIdentifier='com.alaa.browser-smoke',CFBundleExecutable='Smoke',CFBundleName='Smoke',CFBundlePackageType='APPL',CFBundleVersion='1',CFBundleShortVersionString='1.0',MinimumOSVersion='15.0',UIDeviceFamily=[1],UILaunchScreen={}),open(sys.argv[1],'wb'))
PY
codesign --force --sign - "$WORK/Smoke.app"
UDID="$(xcrun simctl create BrowserSmoke com.apple.CoreSimulator.SimDeviceType.iPhone-16)"
trap 'xcrun simctl delete "$UDID" || true' EXIT
xcrun simctl boot "$UDID"
xcrun simctl bootstatus "$UDID" -b
xcrun simctl install "$UDID" "$WORK/Smoke.app"
xcrun simctl launch --console "$UDID" com.alaa.browser-smoke > "$WORK/console.log" 2>&1 &
LAUNCH=$!
for i in $(seq 1 30); do
  if grep -q SMOKE_PASS "$WORK/console.log"; then break; fi
  if ! kill -0 "$LAUNCH" 2>/dev/null; then break; fi
  sleep 1
done
cat "$WORK/console.log"
xcrun simctl io "$UDID" screenshot "$WORK/screenshot.png" || true
grep -q SMOKE_PASS "$WORK/console.log"
xcrun simctl terminate "$UDID" com.alaa.browser-smoke || true
wait "$LAUNCH" || true
