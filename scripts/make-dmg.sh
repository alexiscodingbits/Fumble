#!/usr/bin/env bash
# Builds dist/Fumble.app (via bundle-app.sh) and packages it into a distributable, signed DMG
# with an /Applications drop target. The DMG is the shippable artifact for direct download.
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

bash scripts/bundle-app.sh

VERSION="$(tr -d '[:space:]' < VERSION 2>/dev/null || echo 1.0.0)"
[ -n "$VERSION" ] || VERSION="1.0.0"
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-}"
if [ -z "$CODESIGN_IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q "Fumble Local"; then
  CODESIGN_IDENTITY="Fumble Local"
fi
[ -n "$CODESIGN_IDENTITY" ] || CODESIGN_IDENTITY="-"

DMG="dist/Fumble-${VERSION}.dmg"
# Stage in a non-synced temp dir (iCloud re-taints ~/Documents bundles; see bundle-app.sh).
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "dist/Fumble.app" "$STAGE/Fumble.app"
ln -s /Applications "$STAGE/Applications"

mkdir -p dist
rm -f "$DMG"
hdiutil create \
  -volname "Fumble" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG"

# Sign the DMG itself so Gatekeeper is happy with the container too.
codesign --force --sign "$CODESIGN_IDENTITY" "$DMG"
codesign --verify --verbose=2 "$DMG" || true

echo "Built $DMG (version $VERSION, identity: $CODESIGN_IDENTITY)"
if [ "$CODESIGN_IDENTITY" = "-" ] || [ "$CODESIGN_IDENTITY" = "Fumble Local" ]; then
  echo
  echo "NOTE: not notarized. Other users' Macs will Gatekeeper-block this on download."
  echo "      For public release, build with a Developer ID identity and notarize:"
  echo "      CODESIGN_IDENTITY='Developer ID Application: …' bash scripts/make-dmg.sh"
  echo "      then: xcrun notarytool submit \"$DMG\" --keychain-profile <profile> --wait"
  echo "      then: xcrun stapler staple \"$DMG\""
fi
