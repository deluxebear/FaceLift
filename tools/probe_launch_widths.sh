#!/usr/bin/env bash
# Launch build/FaceLift.app at each saved window width and report crashes.
# A narrow window with the inspector open once crashed on launch with an
# AppKit "Update Constraints in Window" loop; this guards against that.
# Usage: tools/probe_launch_widths.sh [WIDTH ...]   (default: 900 1000 1100)
set -uo pipefail
cd "$(dirname "$0")/.."
BIN=build/FaceLift.app/Contents/MacOS/FaceLift
[ $# -gt 0 ] || set -- 900 1000 1100
status=0
for w in "$@"; do
  for module in FaceLift FaceLift_arm64; do
    defaults write com.jetems.facelift \
      "NSWindow Frame SwiftUI.WindowGroup<SwiftUI.ModifiedContent<${module}.ContentView, SwiftUI._EnvironmentKeyWritingModifier<Foundation.Locale>>>-1-AppWindow-1" \
      "0 241 $w 708 0 0 1512 949 "
  done
  # Skip the "reopen windows?" prompt macOS shows after a crash.
  timeout 8 "$BIN" -ApplePersistenceIgnoreState YES >/dev/null 2>&1
  code=$?
  if [ "$code" -eq 124 ]; then echo "width $w: ok"; else echo "width $w: CRASH (exit $code)"; status=1; fi
done
exit $status
