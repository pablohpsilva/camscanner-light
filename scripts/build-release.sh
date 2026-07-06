#!/usr/bin/env bash
# Build all Android release artifacts at the smallest per-device size:
#   - per-ABI split APKs (sideload)      -> build/app/outputs/flutter-apk/
#   - App Bundle (Play, per-device split) -> build/app/outputs/bundle/release/
# Both are obfuscated with split debug info; symbol maps land in build/symbols/
# (retain these per release to de-symbolicate crash traces).
#
# Usage (from repo root):  bash scripts/build-release.sh
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APP="$ROOT/apps/mobile"
SYMBOLS="$APP/build/symbols"

cd "$APP"

# Inject donation config (Ko-fi URL / Bitcoin address) if present. The real
# values live in the gitignored donation_config.json; without it the donation
# sections stay hidden. See donation_config.example.json.
DEFINES=()
if [[ -f "$APP/donation_config.json" ]]; then
  DEFINES+=(--dart-define-from-file="$APP/donation_config.json")
  echo "== using donation_config.json =="
else
  echo "!! donation_config.json not found -- donation methods will be hidden" >&2
fi

echo "== [1/2] split-per-abi release APKs =="
flutter build apk --release --split-per-abi \
  ${DEFINES[@]+"${DEFINES[@]}"} \
  --obfuscate --split-debug-info="$SYMBOLS"

echo "== [2/2] release App Bundle (.aab) =="
flutter build appbundle --release \
  ${DEFINES[@]+"${DEFINES[@]}"} \
  --obfuscate --split-debug-info="$SYMBOLS"

echo "== artifact sizes =="
ls -lh build/app/outputs/flutter-apk/*-release.apk 2>/dev/null | awk '{print $5, $9}'
ls -lh build/app/outputs/bundle/release/*.aab 2>/dev/null | awk '{print $5, $9}'
echo "== symbol maps (retain per release) =="
ls -1 "$SYMBOLS" 2>/dev/null | sed 's/^/  /'

echo "S1 RELEASE BUILD COMPLETE"
