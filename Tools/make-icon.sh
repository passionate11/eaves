#!/bin/bash
# Renders Tools/make-icon.swift into DeskNote.app's AppIcon.icns.
#
# Separate from build.sh because the icon changes roughly never, and rendering
# ten bitmaps plus an iconutil pass on every build would be pure overhead.
# build.sh calls this only when the .icns is missing or older than its source.
set -euo pipefail

cd "$(dirname "$0")/.."
source Tools/vfs-overlay.sh

WORK=.build/icon
OUT="${1:-Resources}"
mkdir -p "$WORK" "$OUT"

# Compiled rather than run through `swift file.swift`, because the interpreter
# path does not accept the -Xfrontend overlay flags the stale-modulemap
# workaround needs.
swiftc -Onone "${VFS_ARGS[@]}" \
  -target arm64-apple-macosx13.0 \
  -framework AppKit \
  Tools/make-icon.swift -o "$WORK/make-icon"

"$WORK/make-icon" "$WORK"

iconutil -c icns "$WORK/AppIcon.iconset" -o "$OUT/AppIcon.icns"
cp "$WORK/icon-512.png" docs/icon-512.png 2>/dev/null || true

echo "icon: $OUT/AppIcon.icns"
