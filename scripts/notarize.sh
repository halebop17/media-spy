#!/bin/bash
# Notarize + staple MediaSpy for public distribution.
#
# ONE-TIME SETUP — store your Apple credentials in a keychain profile named "MediaSpy".
# Pick ONE of the following:
#
#   (a) Apple ID + app-specific password  (make one at https://appleid.apple.com > Sign-In & Security > App-Specific Passwords)
#       xcrun notarytool store-credentials "MediaSpy" \
#         --apple-id "you@example.com" --team-id "NHQ24QB25V" --password "abcd-efgh-ijkl-mnop"
#
#   (b) App Store Connect API key  (App Store Connect > Users and Access > Integrations > App Store Connect API)
#       xcrun notarytool store-credentials "MediaSpy" \
#         --key "AuthKey_XXXXXXXX.p8" --key-id "XXXXXXXX" --issuer "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
#
# Then just run:  ./scripts/notarize.sh
set -euo pipefail
cd "$(dirname "$0")/.."

PROFILE="${1:-MediaSpy}"     # keychain profile name (default: MediaSpy)
APP="build/Build/Products/Release/MediaSpy.app"
WORK="$(mktemp -d)"

if xcrun stapler validate -q "$APP" 2>/dev/null; then
  echo "==> 1-2/5  App already notarized + stapled — skipping"
else
  echo "==> 1/5  Notarizing the app…"
  ditto -c -k --keepParent "$APP" "$WORK/MediaSpy.zip"
  xcrun notarytool submit "$WORK/MediaSpy.zip" --keychain-profile "$PROFILE" --wait

  echo "==> 2/5  Stapling the app…"
  xcrun stapler staple "$APP"
fi

echo "==> 3/5  Rebuilding the DMG around the stapled app…"
./scripts/make-dmg.sh
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")"
DMG="dist/MediaSpy-${VERSION}.dmg"

echo "==> 4/5  Notarizing the DMG…"
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait

echo "==> 5/5  Stapling the DMG…"
xcrun stapler staple "$DMG"

rm -rf "$WORK"
echo ""
echo "Done. Gatekeeper check:"
spctl -a -t open --context context:primary-signature -vvv "$DMG" || true
echo "Ship: $DMG"
