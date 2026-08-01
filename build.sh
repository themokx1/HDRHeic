#!/bin/bash
# Builds the hdrheic engine and assembles HDRHeic.app, then installs the app
# to ~/Applications. Run:  ./build.sh
set -euo pipefail

cd "$(dirname "$0")"
SRC="Sources/hdrheic/main.swift"
BUILD="build"
APP="$BUILD/HDRHeic.app"
INSTALL_DIR="$HOME/Applications"

echo "==> Compiling engine"
mkdir -p "$BUILD"
xcrun swiftc -O -swift-version 5 "$SRC" -o "$BUILD/hdrheic"

echo "==> Building HDRHeic.app"
rm -rf "$APP"
osacompile -o "$APP" app/HDRHeic.applescript

# Embed the engine binary as an app resource.
cp "$BUILD/hdrheic" "$APP/Contents/Resources/hdrheic"
chmod +x "$APP/Contents/Resources/hdrheic"

# A friendlier bundle identifier and name.
/usr/libexec/PlistBuddy -c "Set :CFBundleName HDRHeic" "$APP/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier string com.zoltanpalotai.hdrheic.app" "$APP/Contents/Info.plist" 2>/dev/null \
  || /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.zoltanpalotai.hdrheic.app" "$APP/Contents/Info.plist" 2>/dev/null || true

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/HDRHeic.app"
cp -R "$APP" "$INSTALL_DIR/HDRHeic.app"

echo "Done. Open: $INSTALL_DIR/HDRHeic.app"
