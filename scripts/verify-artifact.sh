#!/usr/bin/env bash
# Assert that a built Flutter app artifact is a RELEASE build, not a Debug stub.
#
# Why: `flutter install` never compiles -- it side-loads whatever already sits
# in build/, so a stale DEBUG Runner.app can be installed silently. A Debug
# Flutter build then crashes ~2-10ms into cold launch on-device (VSyncClient
# SIGSEGV -- the Dart JIT needs an attached debugger). This script is the
# tripwire: run it before trusting a build, and wire it into a `flutter install`
# pre-hook to block a stale-Debug install.
#
# Detection (iOS .app / .ipa):
#   RELEASE App dylib = multi-MB AOT dylib; DEBUG App = ~34KB stub. A DEBUG build
#   also ships Frameworks/App.framework/flutter_assets/kernel_blob.bin (+ vm_/
#   isolate_snapshot_data). Verdict DEBUG if App < 1MB OR kernel_blob.bin present.
# Detection (Android .apk):
#   DEBUG ships assets/flutter_assets/kernel_blob.bin; RELEASE (AOT) does not.
#   (vm_/isolate_snapshot_data appear in both on Android -- rely on kernel_blob.)
#
# Usage (from repo root):  bash scripts/verify-artifact.sh [PATH]
#   PATH may be a .app dir, an .ipa, or an .apk. Omitted -> auto-detect the
#   first of these that exists:
#     apps/mobile/build/ios/iphoneos/Runner.app
#     apps/mobile/build/ios/ipa/mobile.ipa
#     apps/mobile/build/app/outputs/flutter-apk/app-release.apk
#
# Exit codes:  0 = RELEASE   1 = DEBUG (do not install/ship)   2 = not found / unparseable
set -euo pipefail

# Repo root = git toplevel if available, else the parent of scripts/.
if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
  :
else
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
fi

MIN_RELEASE_BYTES=$((1024 * 1024))  # 1MB: below this the App dylib is a Debug stub.

TMPDIR_UNZIP=""
# Preserve the script's exit status: a trap's last command sets $? on EXIT, so
# guard the test (a false [[ -n "" ]] would otherwise clobber exit 0 -> 1).
cleanup() {
  if [[ -n "$TMPDIR_UNZIP" && -d "$TMPDIR_UNZIP" ]]; then
    rm -rf "$TMPDIR_UNZIP"
  fi
  return 0
}
trap cleanup EXIT

# Portable file size in bytes (macOS stat, with a wc -c fallback).
file_size() {
  local f="$1"
  stat -f%z "$f" 2>/dev/null || wc -c < "$f" | tr -d ' '
}

human_size() { du -sh "$1" 2>/dev/null | awk '{print $1}'; }

# Resolve the artifact path: explicit arg, else first auto-detect candidate.
ARTIFACT=""
if [[ $# -ge 1 ]]; then
  ARTIFACT="$1"
  if [[ ! -e "$ARTIFACT" ]]; then
    echo "!! artifact not found: $ARTIFACT" >&2
    exit 2
  fi
else
  for cand in \
    "$ROOT/apps/mobile/build/ios/iphoneos/Runner.app" \
    "$ROOT/apps/mobile/build/ios/ipa/mobile.ipa" \
    "$ROOT/apps/mobile/build/app/outputs/flutter-apk/app-release.apk"; do
    if [[ -e "$cand" ]]; then ARTIFACT="$cand"; break; fi
  done
  if [[ -z "$ARTIFACT" ]]; then
    echo "== nothing to verify =="
    echo "No built artifact found. Build one first, e.g.:"
    echo "  (iOS)     flutter build ios --release"
    echo "  (iOS IPA) bash scripts/build-ios-release.sh"
    echo "  (Android) flutter build apk --release"
    exit 2
  fi
fi

echo "== verify-artifact =="
echo "  artifact: $ARTIFACT"

# Classify the artifact type from its path/shape.
TYPE=""
case "$ARTIFACT" in
  *.ipa) TYPE="ipa" ;;
  *.apk) TYPE="apk" ;;
  *.app) TYPE="app" ;;
  *)
    if [[ -d "$ARTIFACT" ]]; then
      TYPE="app"
    else
      echo "!! unrecognized artifact type (expected .app, .ipa, or .apk): $ARTIFACT" >&2
      exit 2
    fi
    ;;
esac
echo "  type: $TYPE"
echo "  total size: $(human_size "$ARTIFACT")"

# --- Android .apk -----------------------------------------------------------
if [[ "$TYPE" == "apk" ]]; then
  echo "  apk size: $(file_size "$ARTIFACT") bytes"
  if ! command -v unzip >/dev/null 2>&1; then
    echo "!! unzip not available -- cannot inspect apk" >&2
    exit 2
  fi
  # -l lists without extracting; kernel_blob.bin under flutter_assets => DEBUG.
  if unzip -l "$ARTIFACT" 2>/dev/null | grep -q 'assets/flutter_assets/kernel_blob.bin'; then
    echo
    echo "VERDICT: DEBUG -- do NOT install/ship, rebuild with --release"
    echo "  reason: assets/flutter_assets/kernel_blob.bin present (JIT kernel)"
    echo "  rebuild: flutter build apk --release"
    exit 1
  fi
  echo
  echo "VERDICT: RELEASE (AOT) -- ok to install/ship"
  exit 0
fi

# --- iOS .app / .ipa --------------------------------------------------------
# For an .ipa, unzip to a temp dir; the .app lives under Payload/.
APP_DIR=""
if [[ "$TYPE" == "ipa" ]]; then
  if ! command -v unzip >/dev/null 2>&1; then
    echo "!! unzip not available -- cannot inspect ipa" >&2
    exit 2
  fi
  TMPDIR_UNZIP="$(mktemp -d "${TMPDIR:-/tmp}/verify-artifact.XXXXXX")"
  unzip -q "$ARTIFACT" -d "$TMPDIR_UNZIP"
  APP_DIR="$(find "$TMPDIR_UNZIP/Payload" -maxdepth 1 -type d -name '*.app' 2>/dev/null | head -1)"
  if [[ -z "$APP_DIR" ]]; then
    echo "!! no .app found inside ipa Payload/ -- cannot parse" >&2
    exit 2
  fi
else
  APP_DIR="$ARTIFACT"
fi

APP_DYLIB="$APP_DIR/Frameworks/App.framework/App"
KERNEL_BLOB="$APP_DIR/Frameworks/App.framework/flutter_assets/kernel_blob.bin"

if [[ ! -f "$APP_DYLIB" ]]; then
  echo "!! App dylib not found at Frameworks/App.framework/App -- cannot parse" >&2
  exit 2
fi

DYLIB_BYTES="$(file_size "$APP_DYLIB")"
echo "  App dylib: $DYLIB_BYTES bytes ($(human_size "$APP_DYLIB"))"

IS_DEBUG=0
REASONS=()
if [[ "$DYLIB_BYTES" -lt "$MIN_RELEASE_BYTES" ]]; then
  IS_DEBUG=1
  REASONS+=("App dylib < 1MB ($DYLIB_BYTES bytes) -- Debug stub, not an AOT dylib")
fi
if [[ -f "$KERNEL_BLOB" ]]; then
  IS_DEBUG=1
  REASONS+=("flutter_assets/kernel_blob.bin present (JIT kernel)")
fi

if [[ "$IS_DEBUG" -eq 1 ]]; then
  echo
  echo "VERDICT: DEBUG -- do NOT install/ship, rebuild with --release"
  for r in "${REASONS[@]}"; do echo "  reason: $r"; done
  echo "  rebuild: flutter build ios --release   (or: bash scripts/build-ios-release.sh)"
  exit 1
fi

echo
echo "VERDICT: RELEASE -- ok to install/ship"
exit 0
