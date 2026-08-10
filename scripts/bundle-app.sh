#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$PWD"

if [ -f "$ROOT/VERSION" ]; then
  VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
else
  VERSION=""
fi
[ -n "$VERSION" ] || VERSION="1.0.0"

# Ad-hoc ("-") by default so local builds need no certificate. The release workflow sets
# CODESIGN_IDENTITY to a Developer ID for notarized builds.
CODESIGN_IDENTITY="${CODESIGN_IDENTITY:-"-"}"

# Universal (arm64 + x86_64) release build.
cd FumbleCore
swift build -c release --arch arm64 --arch x86_64 --product FumbleApp
BIN=$(swift build -c release --arch arm64 --arch x86_64 --product FumbleApp --show-bin-path)
cd "$ROOT"

# Assemble + sign in a NON-synced temp dir. The repo lives under ~/Documents, which a macOS
# file provider (iCloud) manages: it asynchronously re-attaches com.apple.FinderInfo to the
# bundle, and `codesign --sign` rejects any bundle carrying that xattr ("detritus not
# allowed"). $TMPDIR is not file-provider-managed, so signing there is race-free.
FINAL="dist/Fumble.app"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
APP="$WORK/Fumble.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/FumbleApp" "$APP/Contents/MacOS/Fumble"

ARCHS=$(lipo -archs "$APP/Contents/MacOS/Fumble")
echo "Binary archs: $ARCHS"
for required in arm64 x86_64; do
  case " $ARCHS " in
    *" $required "*) ;;
    *) echo "ERROR: universal binary missing $required slice (got: $ARCHS)" >&2; exit 1 ;;
  esac
done

# App icon: assets/icon-1024.png -> AppIcon.icns (graceful if absent).
ICON_PLIST_KEY=""
ICON_SRC="$ROOT/assets/icon-1024.png"
if [ -f "$ICON_SRC" ]; then
  ICONSET="$(mktemp -d)/AppIcon.iconset"
  mkdir -p "$ICONSET"
  for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
              "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
              "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" "$ICON_SRC" --out "$ICONSET/$2.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
  rm -rf "$ICONSET"
  ICON_PLIST_KEY='  <key>CFBundleIconFile</key><string>AppIcon</string>'
  echo "Embedded AppIcon.icns"
else
  echo "WARNING: $ICON_SRC not found — building without an app icon." >&2
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>com.alexiscodingbits.fumble</string>
  <key>CFBundleExecutable</key><string>Fumble</string>
  <key>CFBundleName</key><string>Fumble</string>
  <key>CFBundleDisplayName</key><string>Fumble</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
${ICON_PLIST_KEY}
  <key>LSUIElement</key><true/>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
plutil -lint "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# Strip xattrs, then sign LAST (after icon + plist are in place). --options runtime (hardened
# runtime) is required for notarization.
xattr -cr "$APP"
codesign --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP"
codesign --verify --strict --verbose=2 "$APP"

mkdir -p dist
rm -rf "$FINAL"
ditto "$APP" "$FINAL"
echo "Built + signed $FINAL (version $VERSION)"
echo
echo "NOTE: ad-hoc signatures change on every rebuild, and macOS ties Input Monitoring"
echo "      permission to the code signature. Expect to re-grant permission after each"
echo "      rebuild until this ships with a stable Developer ID. See CLAUDE.md."
