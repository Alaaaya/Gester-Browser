#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="BQTool"
VERSION="2.4.1"
BID="${BID:-com.kamui.escape}"
BUILD="$ROOT/build"
APP="$BUILD/Payload/$APP_NAME.app"

# SDK discovery: check explicit $SDK, theos fallback, then xcrun iphoneos SDK
if [ -z "${SDK:-}" ] || [ ! -d "$SDK" ]; then
    if [ -d "/opt/theos/sdks/iPhoneOS14.5.sdk" ]; then
        SDK="/opt/theos/sdks/iPhoneOS14.5.sdk"
    elif command -v xcrun >/dev/null 2>&1; then
        SDK="$(xcrun --sdk iphoneos --show-sdk-path 2>/dev/null || true)"
    fi
fi

echo "[*] SDK: ${SDK:-none}"
[ -n "${SDK:-}" ] && [ -d "$SDK" ] || { echo "[!] SDK missing. Install Xcode or set SDK=/path/to/iPhoneOS.sdk"; exit 1; }

rm -rf "$BUILD"
mkdir -p "$APP"

EXTRA_LDFLAGS=""
if [ -n "${USE_LLD:-}" ]; then
    EXTRA_LDFLAGS="-fuse-ld=lld"
fi

echo "[*] compiling..."
clang \
    -target arm64-apple-ios14.0 \
    -isysroot "$SDK" \
    -I"$ROOT/src" \
    -fobjc-arc -fblocks -O2 \
    -Wall -Wno-unused-parameter -Wno-deprecated-declarations \
    -framework UIKit \
    -framework Foundation \
    -framework CoreFoundation \
    -framework CoreGraphics \
    -framework WebKit \
    -framework ImageIO \
    -L"$SDK/usr/lib" -lz \
    ${EXTRA_LDFLAGS} \
    "$ROOT/src/main.m" \
    "$ROOT/src/AppDelegate.m" \
    "$ROOT/src/SceneDelegate.m" \
    "$ROOT/src/RootTabBarController.m" \
    "$ROOT/src/ReadOnlyBrowserVC.m" \
    "$ROOT/src/GestaltVC.m" \
    "$ROOT/src/CacheExtraEditVC.m" \
    "$ROOT/src/PosterBoardVC.m" \
    "$ROOT/src/TendiesExploreVC.m" \
    "$ROOT/src/SettingsVC.m" \
    "$ROOT/src/LogVC.m" \
    "$ROOT/src/BQUI.m" \
    "$ROOT/src/BQCore.m" \
    -o "$APP/$APP_NAME"

cp "$ROOT/src/Info.plist" "$APP/Info.plist"
cp "$ROOT/src/respring.html" "$APP/respring.html"
for lproj in "$ROOT"/src/*.lproj; do
    [ -d "$lproj" ] && cp -R "$lproj" "$APP/"
done

if [ -d "$ROOT/src/icons" ]; then
    cp -R "$ROOT/src/icons/"* "$APP/"
fi

if command -v actool >/dev/null 2>&1 && [ -d "$ROOT/src/Assets.xcassets" ]; then
    echo "[*] compiling asset catalog..."
    actool "$ROOT/src/Assets.xcassets" \
        --compile "$APP" \
        --platform iphoneos \
        --target-device iphone \
        --target-device ipad \
        --minimum-deployment-target 15.0 \
        --app-icon AppIcon \
        --output-partial-info-plist "$BUILD/assets_info.plist" >/dev/null
fi

echo "[*] signing..."
ENTITLEMENTS="$ROOT/src/entitlements.plist"
if command -v ldid >/dev/null 2>&1; then
    echo "[*] applying ldid signature with entitlements..."
    ldid -S"$ENTITLEMENTS" "$APP/$APP_NAME"
fi
if command -v codesign >/dev/null 2>&1; then
    SIGN_IDENTITY="${SIGN_IDENTITY:--}"
    echo "[*] applying codesign ($SIGN_IDENTITY)..."
    codesign -f -s "$SIGN_IDENTITY" --entitlements "$ENTITLEMENTS" "$APP"
fi

echo "[*] packing..."
(cd "$BUILD" && zip -qry "Gester-$VERSION.ipa" Payload)
echo "[*] done: $BUILD/Gester-$VERSION.ipa"
