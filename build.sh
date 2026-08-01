#!/bin/bash
# Builds the hdrheic engine + the SwiftUI HDRHeic.app, installs to ~/Applications.
# Run:  ./build.sh
set -euo pipefail

cd "$(dirname "$0")"
BUILD="build"
APP="$BUILD/HDRHeic.app"
INSTALL_DIR="$HOME/Applications"

echo "==> Compiling engine (hdrheic)"
mkdir -p "$BUILD"
xcrun swiftc -O -swift-version 5 Sources/hdrheic/main.swift -o "$BUILD/hdrheic"

echo "==> Compiling SwiftUI app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -swift-version 5 -parse-as-library \
    Sources/HDRHeicApp/App.swift \
    -framework SwiftUI -framework AppKit \
    -o "$APP/Contents/MacOS/HDRHeic"

echo "==> Assembling bundle"
cp "$BUILD/hdrheic" "$APP/Contents/Resources/hdrheic"
chmod +x "$APP/Contents/Resources/hdrheic"

# App icon (if present).
ICON_LINE=""
if [ -f icon/AppIcon.icns ]; then
    cp icon/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
    ICON_LINE="	<key>CFBundleIconFile</key><string>AppIcon</string>"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key><string>HDRHeic</string>
	<key>CFBundleDisplayName</key><string>HDRHeic</string>
	<key>CFBundleIdentifier</key><string>com.zoltanpalotai.hdrheic.app</string>
	<key>CFBundleExecutable</key><string>HDRHeic</string>
	<key>CFBundlePackageType</key><string>APPL</string>
	<key>CFBundleShortVersionString</key><string>1.5</string>
	<key>CFBundleVersion</key><string>6</string>
$ICON_LINE
	<key>LSMinimumSystemVersion</key><string>13.0</string>
	<key>NSPrincipalClass</key><string>NSApplication</string>
	<key>NSHighResolutionCapable</key><true/>
	<key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# Ad-hoc sign so the app launches cleanly.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "==> Installing to $INSTALL_DIR"
mkdir -p "$INSTALL_DIR"
rm -rf "$INSTALL_DIR/HDRHeic.app"
cp -R "$APP" "$INSTALL_DIR/HDRHeic.app"

# Put the `hdrheic` CLI on PATH (symlink to the installed engine — survives rebuilds).
BIN_DIR="$HOME/.local/bin"
mkdir -p "$BIN_DIR"
ln -sf "$INSTALL_DIR/HDRHeic.app/Contents/Resources/hdrheic" "$BIN_DIR/hdrheic"

echo "==> Building DMG (drag-to-Applications installer)"
DMG_STAGE="$BUILD/dmg"
rm -rf "$DMG_STAGE" "$BUILD/HDRHeic.dmg"
mkdir -p "$DMG_STAGE"
cp -R "$APP" "$DMG_STAGE/HDRHeic.app"
ln -s /Applications "$DMG_STAGE/Applications"
hdiutil create -volname "HDRHeic" -srcfolder "$DMG_STAGE" -ov -format UDZO "$BUILD/HDRHeic.dmg" >/dev/null
rm -rf "$DMG_STAGE"

echo "Done."
echo "  App: $INSTALL_DIR/HDRHeic.app"
echo "  CLI: $BIN_DIR/hdrheic  (run 'hdrheic scan')"
echo "  DMG: $BUILD/HDRHeic.dmg"
case ":$PATH:" in
  *":$BIN_DIR:"*) : ;;
  *) echo "  NOTE: add $BIN_DIR to your PATH to use 'hdrheic' directly." ;;
esac
