#!/bin/bash
#
# FaderLab installer / updater.
#
# Run this to download and launch the newest build. Run it again any time you
# want to update — it replaces the installed copy in place.
#
#   curl -fsSL https://raw.githubusercontent.com/brianbruzzi/iPhone-App/claude/faders-launchpad-midi-automation-u4z9u7/install.sh | bash
#
# Why this exists instead of "download the zip in your browser":
# macOS tags browser downloads with a `com.apple.quarantine` attribute, and it's
# that tag — not the app itself — that triggers Gatekeeper's "unidentified
# developer" block. `curl` does not set the tag, so downloading this way means
# Gatekeeper is never invoked at all, rather than being invoked and overridden
# through System Settings every single time.

set -euo pipefail

REPO="brianbruzzi/iPhone-App"
TAG="latest-build"
ASSET="FaderLab.zip"
URL="https://github.com/${REPO}/releases/download/${TAG}/${ASSET}"
DEST="$HOME/Applications"
APP="$DEST/FaderLab.app"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading the latest FaderLab..."
if ! curl -fL --retry 3 --retry-delay 2 -o "$TMP/$ASSET" "$URL"; then
    echo ""
    echo "Couldn't download the app." >&2
    echo "The build may still be running — check:" >&2
    echo "  https://github.com/${REPO}/actions" >&2
    exit 1
fi

# Quit EVERY running copy so we're not replacing the bundle out from under one — and so
# the freshly installed app doesn't end up running alongside a survivor. Two instances
# both driving the fader motors at 60Hz from different clocks makes the hardware buzz
# violently (this happened: a stray instance launched from a since-deleted build folder
# ignored the polite AppleScript quit, which addresses the app by name and can miss
# instances running from other paths). So: ask nicely, then kill by process name, then
# verify nothing is left before touching the bundle.
osascript -e 'quit app "FaderLab"' >/dev/null 2>&1 || true
sleep 1
pkill -x FaderLab >/dev/null 2>&1 || true
for _ in 1 2 3 4 5 6 7 8 9 10; do
  pgrep -x FaderLab >/dev/null 2>&1 || break
  sleep 0.5
done
if pgrep -x FaderLab >/dev/null 2>&1; then
  echo "WARNING: a FaderLab instance would not quit; continuing, but if the faders act up," >&2
  echo "         quit every FaderLab window and relaunch from ~/Applications." >&2
fi

echo "==> Installing to $DEST ..."
mkdir -p "$DEST"
ditto -x -k "$TMP/$ASSET" "$TMP/unpacked"
rm -rf "$APP"
mv "$TMP/unpacked/FaderLab.app" "$APP"

# Belt and braces: curl doesn't set the quarantine flag, but stripping it anyway
# means this script still works if the zip ever arrives via a browser instead.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

# Drop a double-clickable updater so future updates don't need Terminal at all.
# Written locally rather than downloaded, so it carries no quarantine flag and
# stays double-clickable forever.
UPDATER="$DEST/Update FaderLab.command"
cat > "$UPDATER" <<UPDATER_EOF
#!/bin/bash
curl -fsSL https://raw.githubusercontent.com/${REPO}/claude/faders-launchpad-midi-automation-u4z9u7/install.sh | bash
UPDATER_EOF
chmod +x "$UPDATER"

echo "==> Launching FaderLab..."
open "$APP"

echo ""
echo "Done. FaderLab is installed in $DEST"
echo "To update later, double-click:  $UPDATER"
