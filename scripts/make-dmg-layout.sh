#!/usr/bin/env bash
# Regenerates packaging/dmg/DS_Store — the Finder layout for the DMG window (window size,
# icon positions, icon size, background picture). make-dmg.sh copies this file into every
# DMG it builds, so the layout only has to be produced once, here, on a Mac with Finder;
# CI never has to script Finder (which is flaky on headless runners).
#
# Re-run only when the layout changes (background, positions, window size). Requires
# dist/Fumble.app (bash scripts/bundle-app.sh) and packaging/dmg/background.png
# (swift scripts/make-dmg-background.swift). Commit the resulting DS_Store.
#
# ⚠️ The .DS_Store's background reference resolves by path on the mounted volume, so the
# volume name ("Fumble") and the path .background/background.png must match make-dmg.sh.
set -euo pipefail
cd "$(dirname "$0")/.."

[ -d dist/Fumble.app ] || { echo "dist/Fumble.app missing — run scripts/bundle-app.sh first" >&2; exit 1; }
[ -f packaging/dmg/background.png ] || { echo "packaging/dmg/background.png missing — run swift scripts/make-dmg-background.swift" >&2; exit 1; }

STAGE="$(mktemp -d)"
RW_DMG="$(mktemp -d)/fumble-layout.dmg"
trap 'hdiutil detach /Volumes/Fumble >/dev/null 2>&1 || true; rm -rf "$STAGE" "$(dirname "$RW_DMG")"' EXIT

ditto dist/Fumble.app "$STAGE/Fumble.app"
ln -s /Applications "$STAGE/Applications"
mkdir "$STAGE/.background"
cp packaging/dmg/background.png "$STAGE/.background/background.png"

hdiutil detach /Volumes/Fumble >/dev/null 2>&1 || true
hdiutil create -volname "Fumble" -srcfolder "$STAGE" -ov -format UDRW "$RW_DMG"
hdiutil attach "$RW_DMG" -noautoopen

# Window content 600×400 to match the background; icon centres must match the arrow the
# background draws (Fumble at 150,180 → Applications at 450,180).
osascript <<'EOF'
tell application "Finder"
  -- hdiutil returns before Finder registers the volume; wait for it
  repeat 30 times
    if exists disk "Fumble" then exit repeat
    delay 0.5
  end repeat
  tell disk "Fumble"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 800, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 100
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:background.png"
    set position of item "Fumble.app" of container window to {150, 180}
    set position of item "Applications" of container window to {450, 180}
    -- reopen so Finder flushes the view settings to .DS_Store
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
EOF

sync
# Finder writes .DS_Store lazily; wait for it to exist before copying.
for _ in $(seq 1 20); do
  [ -f /Volumes/Fumble/.DS_Store ] && break
  sleep 0.5
done
[ -f /Volumes/Fumble/.DS_Store ] || { echo "Finder never wrote .DS_Store" >&2; exit 1; }
cp /Volumes/Fumble/.DS_Store packaging/dmg/DS_Store
hdiutil detach /Volumes/Fumble

echo "Wrote packaging/dmg/DS_Store — commit it alongside packaging/dmg/background.png"
