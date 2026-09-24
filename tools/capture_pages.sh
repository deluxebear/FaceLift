#!/usr/bin/env bash
# Screenshot every FaceLift page (⌘1–⌘4) from build/FaceLift.app.
# Usage: tools/capture_pages.sh OUT_DIR [light|dark] [WIDTHxHEIGHT]   (default 1400x900)
# Needs Accessibility permission for the terminal (System Events keystrokes).
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:?usage: tools/capture_pages.sh OUT_DIR [light|dark] [WIDTHxHEIGHT]}"
MODE="${2:-light}"
SIZE="${3:-1400x900}"
mkdir -p "$OUT"

osascript -e 'tell application "FaceLift" to quit' >/dev/null 2>&1 || true
# Relaunching before the old instance exits drops the launch arguments.
for _ in $(seq 1 20); do pgrep -f 'FaceLift.app/Contents/MacOS' >/dev/null || break; sleep 0.5; done
# The app follows the system appearance, so switch it for the capture and
# restore the user's setting on exit.
WAS_DARK="$(osascript -e 'tell application "System Events" to tell appearance preferences to get dark mode')"
WANT_DARK=false; [ "$MODE" = dark ] && WANT_DARK=true
restore_appearance() {
  osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $WAS_DARK" >/dev/null
}
trap restore_appearance EXIT
osascript -e "tell application \"System Events\" to tell appearance preferences to set dark mode to $WANT_DARK" >/dev/null
for _ in 1 2 3; do
  open build/FaceLift.app --args -ApplePersistenceIgnoreState YES && break
  sleep 2
done
sleep 3

HELPER="$(mktemp -d -t facelift)/wid.swift"
cat > "$HELPER" <<'SWIFT'
import CoreGraphics
let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as! [[String: Any]]
for w in windows where (w["kCGWindowOwnerName"] as? String) == "FaceLift" && (w["kCGWindowLayer"] as? Int) == 0 {
    print(w["kCGWindowNumber"]!); break
}
SWIFT
# Wait up to ~15 s for the main window to appear.
WID=""
for _ in $(seq 1 15); do
  WID="$(swift "$HELPER")"
  [ -n "$WID" ] && break
  sleep 1
done
rm -f "$HELPER"
[ -n "$WID" ] || { echo "FaceLift window not found" >&2; exit 1; }

osascript -e "tell application \"System Events\" to tell process \"FaceLift\" to set size of window 1 to {${SIZE%x*}, ${SIZE#*x}}"
sleep 1

for i in 1 2 3 4; do
  osascript -e 'tell application "FaceLift" to activate' \
            -e "tell application \"System Events\" to keystroke \"$i\" using command down"
  sleep 1.5
  screencapture -o -l"$WID" "$OUT/${MODE}-${SIZE}-page$i.png"
done
echo "Saved to $OUT"
