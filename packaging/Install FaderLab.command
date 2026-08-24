#!/bin/bash
# Installs the FaderLab.app sitting NEXT TO this script — no internet needed.
# For putting FaderLab on a Mac with no connection (e.g. on set): download the
# release zip once on any online Mac, copy it to a USB stick, unzip on the target
# Mac, then double-click this file. If macOS blocks the double-click, run it via
# Terminal instead:  bash "/path/to/Install FaderLab.command"
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$HERE/FaderLab.app"
DEST_DIR="$HOME/Applications"
DEST_APP="$DEST_DIR/FaderLab.app"

if [ ! -d "$SOURCE_APP" ]; then
  echo "ERROR: FaderLab.app not found next to this script ($HERE)."
  echo "Keep this file in the same folder as FaderLab.app (as unzipped) and run it again."
  exit 1
fi

echo "Installing FaderLab from: $SOURCE_APP"

# Quit any running copy so the binary isn't busy while we replace it.
if pgrep -x FaderLab >/dev/null 2>&1; then
  echo "Quitting the running copy of FaderLab..."
  osascript -e 'tell application "FaderLab" to quit' >/dev/null 2>&1 || true
  sleep 1
  pkill -x FaderLab >/dev/null 2>&1 || true
fi

mkdir -p "$DEST_DIR"
rm -rf "$DEST_APP"
ditto "$SOURCE_APP" "$DEST_APP"

# Strip the quarantine flag so Gatekeeper doesn't block the (non-notarized) app.
xattr -dr com.apple.quarantine "$DEST_APP" 2>/dev/null || true

echo "Installed to: $DEST_APP"
echo "Launching FaderLab..."
open "$DEST_APP"
echo "Done. FaderLab needs no internet to run — audio is local files, MIDI is local hardware."
