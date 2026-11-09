#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$RUNNER_TEMP/browser-smoke"
mkdir -p "$WORK/Smoke.app"
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
xcrun clang -target "$ARCH-apple-ios15.0-simulator" -isysroot "$SDK" -fobjc-arc -fblocks -g -O0 -I"$ROOT/src" -framework UIKit -framework Foundation -framework ImageIO -framework CoreGraphics "$ROOT/tests/browser_smoke.m" "$ROOT/src/ReadOnlyBrowserVC.m" -o "$WORK/Smoke.app/Smoke"
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
for LANGUAGE in en ar; do
  LOG="$WORK/console-$LANGUAGE.log"
  xcrun simctl launch --console "$UDID" com.alaa.browser-smoke -AppleLanguages "($LANGUAGE)" -AppleLocale "$LANGUAGE" > "$LOG" 2>&1 &
  LAUNCH=$!
  for i in $(seq 1 45); do
    if grep -q SMOKE_PASS "$LOG"; then break; fi
    if ! kill -0 "$LAUNCH" 2>/dev/null; then break; fi
    sleep 1
  done
  cat "$LOG"
  xcrun simctl io "$UDID" screenshot "$WORK/screenshot-$LANGUAGE.png"
  grep -q SMOKE_SAFE_GATES_PASS "$LOG"
  grep -q SMOKE_LAYOUT_PASS "$LOG"
  grep -q SMOKE_PASS "$LOG"
  xcrun simctl terminate "$UDID" com.alaa.browser-smoke || true
  wait "$LAUNCH" || true
done
