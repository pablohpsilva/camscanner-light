#!/usr/bin/env bash
# Capture raw store screenshots for one device class.
#
# Runs the store_capture integration test on the given device, watches its
# stdout for `@@SHOT:<name>@@` markers, and grabs an OS-level screenshot into
# store/raw/<class>/<name>.png at each marker. OS capture (simctl/adb) is used
# so native views (the pdfx PDF preview) render correctly.
#
# Usage:
#   store/capture.sh <flutter-device-id> <class> <ios|android>
# e.g.
#   store/capture.sh <ipad-udid>       ios-ipad        ios
#   store/capture.sh emulator-5554     android-phone   android
set -uo pipefail

DEVICE="${1:?flutter device id}"
CLASS="${2:?class dir, e.g. ios-iphone}"
PLATFORM="${3:?ios|android}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/store/raw/$CLASS"
mkdir -p "$OUT"

shoot() { # $1 = screen name
  local out="$OUT/$1.png"
  if [ "$PLATFORM" = ios ]; then
    xcrun simctl io "$DEVICE" screenshot "$out" >/dev/null 2>&1
  else
    adb -s "$DEVICE" exec-out screencap -p > "$out" 2>/dev/null
  fi
  if [ -s "$out" ]; then echo "  captured $CLASS/$1.png"; else echo "  !! capture FAILED for $1"; fi
}

echo "== capturing $CLASS on $DEVICE ($PLATFORM) =="
# A pseudo-tty (script -q /dev/null) forces line-buffered output so markers
# stream live instead of arriving batched at test end.
cd "$ROOT/apps/mobile"
script -q /dev/null flutter test integration_test/store_capture_test.dart \
  -d "$DEVICE" 2>&1 | \
while IFS= read -r line; do
  printf '%s\n' "$line"
  if [[ "$line" == *"@@SHOT:"* ]]; then
    name="${line#*@@SHOT:}"; name="${name%%@@*}"
    # brief settle so the held frame is fully painted before the grab
    sleep 0.8
    shoot "$name"
  fi
done

echo "== done: $(ls -1 "$OUT" 2>/dev/null | wc -l | tr -d ' ') raw shots in $OUT =="
