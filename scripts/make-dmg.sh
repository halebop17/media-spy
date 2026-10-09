#!/bin/bash
# Build the MediaSpy distribution DMG from the Release app.
# Uses the app icon as both the volume icon and the .dmg file icon.
# Run after scripts/sign.sh; the .dmg itself is signed with the same Developer ID.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="build/Build/Products/Release/MediaSpy.app"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
OUT="dist/MediaSpy-${VERSION}.dmg"
WORK="$(mktemp -d)"
ISET="$WORK/MediaSpy.iconset"
ICNS="$WORK/MediaSpy.icns"
STAGE="$WORK/stage"
SRC="Support/Assets.xcassets/AppIcon.appiconset"

# --- Build .icns from the app icon PNGs ---
mkdir -p "$ISET"
cp "$SRC/icon_16.png"   "$ISET/icon_16x16.png"
cp "$SRC/icon_32.png"   "$ISET/icon_16x16@2x.png"
cp "$SRC/icon_32.png"   "$ISET/icon_32x32.png"
cp "$SRC/icon_64.png"   "$ISET/icon_32x32@2x.png"
cp "$SRC/icon_128.png"  "$ISET/icon_128x128.png"
cp "$SRC/icon_256.png"  "$ISET/icon_128x128@2x.png"
cp "$SRC/icon_256.png"  "$ISET/icon_256x256.png"
cp "$SRC/icon_512.png"  "$ISET/icon_256x256@2x.png"
cp "$SRC/icon_512.png"  "$ISET/icon_512x512.png"
cp "$SRC/icon_1024.png" "$ISET/icon_512x512@2x.png"
iconutil -c icns "$ISET" -o "$ICNS"

# --- Stage app ---
mkdir -p "$STAGE" dist
cp -R "$APP" "$STAGE/MediaSpy.app"

# --- Build DMG ---
rm -f "$OUT"
create-dmg \
  --volname "MediaSpy" \
  --volicon "$ICNS" \
  --window-pos 200 120 \
  --window-size 540 360 \
  --icon-size 110 \
  --icon "MediaSpy.app" 140 175 \
  --hide-extension "MediaSpy.app" \
  --app-drop-link 400 175 \
  "$OUT" "$STAGE"

# --- Stamp the app icon onto the .dmg file itself ---
cat > "$WORK/seticon.swift" <<'SWIFT'
import Cocoa
let a = CommandLine.arguments
let img = NSImage(contentsOfFile: a[1])!
exit(NSWorkspace.shared.setIcon(img, forFile: a[2], options: []) ? 0 : 2)
SWIFT
xcrun swift "$WORK/seticon.swift" "$ICNS" "$OUT"

# --- Sign the .dmg itself (Gatekeeper's check on the download needs it) ---
IDENTITY="${IDENTITY:-Developer ID Application: Chananpat Atirojsakul (NHQ24QB25V)}"
codesign --force --timestamp --sign "$IDENTITY" "$OUT"

rm -rf "$WORK"
echo "Built: $OUT"
