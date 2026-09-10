#!/usr/bin/env bash
# Assert that a BUILT artifact actually carries the donation config.
#
# Why this exists: the donation sections are gated on the VALUE, not a flag —
# `if (iosBtcDonation && bitcoinAddress.isNotEmpty)`. `bitcoinAddress` comes
# from `String.fromEnvironment('BITCOIN_ADDRESS')`, so a build made without
# `--dart-define-from-file=donation_config.json` compiles and runs perfectly
# and simply HIDES Bitcoin and Ko-fi. No error, no crash, nothing in the logs —
# the feature is just silently missing.
#
# That is not hypothetical: it shipped to a test device on 2026-09-10 and was
# reported as "I can't see the bitcoin on iOS". `scripts/build-release.sh` and
# `scripts/build-ios-release.sh` DO pass the defines; ad-hoc
# `flutter build ios --release` / `flutter build apk --release` do NOT. This
# script tells the two apart by reading the compiled binary.
#
# Usage (from repo root):
#   bash scripts/verify-donation-config.sh                 # iOS Runner.app (default)
#   bash scripts/verify-donation-config.sh <path-to-apk>
#   bash scripts/verify-donation-config.sh <path-to-App-binary>
#
# Exit: 0 = both values found   1 = something missing   2 = inputs unusable
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APP="$ROOT/apps/mobile"
CONFIG="$APP/donation_config.json"
TARGET="${1:-$APP/build/ios/iphoneos/Runner.app/Frameworks/App.framework/App}"

if [[ ! -f "$CONFIG" ]]; then
  echo "verify-donation-config: no $CONFIG" >&2
  echo "  Without it every release build hides Ko-fi and Bitcoin." >&2
  exit 2
fi
if [[ ! -e "$TARGET" ]]; then
  echo "verify-donation-config: no artifact at $TARGET" >&2
  echo "  Build one first, e.g. bash scripts/build-release.sh" >&2
  exit 2
fi

KOFI="$(python3 -c "import json;print(json.load(open('$CONFIG')).get('KOFI_URL',''))")"
ADDR="$(python3 -c "import json;print(json.load(open('$CONFIG')).get('BITCOIN_ADDRESS',''))")"

echo "== verify-donation-config =="
echo "  artifact: $TARGET"

# APKs are zips: scan the Dart AOT blob inside rather than the container.
SCAN="$TARGET"
WORK=""
if [[ "$TARGET" == *.apk ]]; then
  WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT
  unzip -q -o "$TARGET" 'assets/flutter_assets/*' 'lib/*/libapp.so' -d "$WORK" 2>/dev/null || true
  SCAN="$WORK"
fi

missing=0
check() {
  local label="$1" value="$2"
  if [[ -z "$value" ]]; then
    echo "  SKIP    $label — empty in donation_config.json (section intentionally hidden)"
    return
  fi
  if grep -rqF "$value" "$SCAN" 2>/dev/null; then
    echo "  ok      $label present in the binary"
  else
    echo "  MISSING $label NOT in the binary"
    missing=$((missing + 1))
  fi
}

check "KOFI_URL"        "$KOFI"
check "BITCOIN_ADDRESS" "$ADDR"

if [[ $missing -gt 0 ]]; then
  echo
  echo "FAIL: this build will silently hide $missing donation section(s)."
  echo "Rebuild through the release scripts, which pass the defines:"
  echo "  bash scripts/build-release.sh        # Android"
  echo "  bash scripts/build-ios-release.sh    # iOS"
  echo "Or add: --dart-define-from-file=donation_config.json"
  exit 1
fi

echo
echo "OK: the donation config is compiled into this build."
