#!/bin/bash
# Captures README screenshots of Eaves, one per theme.
#
#   ./Tools/shoot.sh            all themes into docs/
#   ./Tools/shoot.sh sand ink   just those two
#
# Two things this handles that a plain `screencapture -R` does not:
#
#  * It captures by window ID, so whatever else is on the desktop stays out of
#    the shot.
#  * It parks the window on a Retina screen first. A 1x capture of a 380pt
#    window is 380px wide and looks soft in a README on any modern display.
#
# It edits ~/Library/Application Support/Eaves/{settings,notes}.json and
# restarts the app between shots, so it backs both up and restores them on the
# way out — including on Ctrl-C.
set -euo pipefail

cd "$(dirname "$0")/.."
source Tools/vfs-overlay.sh

APP_PATH="${EAVES_APP:-/Applications/Eaves.app}"
SUPPORT="$HOME/Library/Application Support/Eaves"
OUT=docs
THEMES=("$@")
[ "${#THEMES[@]}" -eq 0 ] && THEMES=(sand ink glass)

mkdir -p "$OUT" .build/shoot
BACKUP=.build/shoot/backup
mkdir -p "$BACKUP"

for f in settings.json notes.json; do
  [ -f "$SUPPORT/$f" ] && cp "$SUPPORT/$f" "$BACKUP/$f"
done

restore() {
  pkill -f "$APP_PATH" 2>/dev/null || true
  sleep 1
  for f in settings.json notes.json; do
    [ -f "$BACKUP/$f" ] && cp "$BACKUP/$f" "$SUPPORT/$f"
  done
  open "$APP_PATH" 2>/dev/null || true
  echo "restored your notes and settings"
}
trap restore EXIT

for t in Tools/window-id.swift Tools/screens.swift; do
  bin=".build/$(basename "$t" .swift)"
  [ -x "$bin" ] && [ "$bin" -nt "$t" ] && continue
  swiftc -Onone "${VFS_ARGS[@]}" -target arm64-apple-macosx13.0 \
    -framework AppKit "$t" -o "$bin"
done

# Highest-scale screen wins; ties go to the first, which is the main display.
# Field 6 when splitting on "=" is the scale factor — the line looks like
# "1 x=-1512 y=-196 w=1512 h=982 scale=2.0".
read -r SX SY SW SH <<<"$(.build/screens | sort -t= -k6 -rn | head -1 |
  sed -E 's/^[0-9]+ x=(-?[0-9]+) y=(-?[0-9]+) w=([0-9]+) h=([0-9]+).*/\1 \2 \3 \4/')"

WIN_W=380
WIN_H=330
WIN_X=$((SX + (SW - WIN_W) / 2))
WIN_Y=$((SY + (SH - WIN_H) / 2))

python3 Tools/demo-content.py "$SUPPORT/notes.json"

for theme in "${THEMES[@]}"; do
  pkill -f "$APP_PATH" 2>/dev/null || true
  sleep 1.2

  python3 - "$SUPPORT/settings.json" "$theme" "$WIN_X" "$WIN_Y" "$WIN_W" "$WIN_H" <<'PY'
import json, sys
path, theme, x, y, w, h = sys.argv[1], sys.argv[2], *map(int, sys.argv[3:7])
s = json.load(open(path))
s.update({"theme": theme, "dock": "none", "allHidden": False, "collapsed": False,
          "winX": x, "winY": y, "winW": w, "winH": h})
json.dump(s, open(path, "w"), indent=2)
PY

  open "$APP_PATH"
  # The window has to be up *and* painted before the shot; a shorter wait
  # catches it mid-fade and produces a washed-out capture.
  sleep 3

  # Hand focus to Finder first. Left alone, Eaves restores focus to the
  # first row's field editor on launch, and the shot comes out with a blue
  # selection highlight sitting on the first todo.
  osascript -e 'tell application "Finder" to activate' >/dev/null 2>&1 || true
  sleep 1.2

  id=$(.build/window-id Eaves | head -1 | cut -d' ' -f1)
  if [ -z "$id" ]; then
    echo "!! no Eaves window found for theme $theme" >&2
    continue
  fi
  screencapture -x -o -l "$id" "$OUT/screenshot-$theme.png"
  echo "$OUT/screenshot-$theme.png  $(sips -g pixelWidth "$OUT/screenshot-$theme.png" |
    tail -1 | tr -d ' ')"
done
