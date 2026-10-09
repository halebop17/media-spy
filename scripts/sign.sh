#!/bin/bash
# Re-sign the Release app with Developer ID (hardened runtime + secure timestamp).
# Xcode builds ad-hoc (see project.yml), so run this after every Release build and
# before scripts/notarize.sh. Signs inside-out: engine dylibs → MediaSpyKit.framework
# → Quick Look appex (sandboxed, keeps its entitlements) → the app itself.
set -euo pipefail
cd "$(dirname "$0")/.."

IDENTITY="${IDENTITY:-Developer ID Application: Chananpat Atirojsakul (NHQ24QB25V)}"
APP="build/Build/Products/Release/MediaSpy.app"
SIGN=(codesign --force --options runtime --timestamp --sign "$IDENTITY")

"${SIGN[@]}" "$APP/Contents/Frameworks/libzen.0.dylib"
"${SIGN[@]}" "$APP/Contents/Frameworks/libmediainfo.0.dylib"
"${SIGN[@]}" "$APP/Contents/Frameworks/MediaSpyKit.framework"
"${SIGN[@]}" --entitlements Support/MediaSpyQL.entitlements "$APP/Contents/PlugIns/MediaSpyQL.appex"
"${SIGN[@]}" "$APP"

codesign --verify --deep --strict --verbose=2 "$APP"
echo "Signed: $APP"
