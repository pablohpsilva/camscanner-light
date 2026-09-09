#!/usr/bin/env bash
# Assert that R8 did NOT strip the classes the document scanner needs.
#
# Why this exists: the OS document scanner has broken in RELEASE ONLY, twice.
# cunning_document_scanner's own Kotlin lives under biz.cunning.**, which the
# io.flutter.plugins.** keep rule does not cover, and ML Kit's scanner classes
# are reached reflectively through Play Services. When R8 removes them the app
# still builds and still passes every test: the scan device BDD injects FAKE
# scanners and runs DEBUG builds, so nothing in the suite touches the real
# plugin. The failure only appears in a user's hands -- a single page captured
# instead of many, or a crash on the second launch (the ID-card back step).
#
# This turns that invisible failure into a check: read the shipped dex and
# confirm the classes are actually present under their original names.
#
# Usage:  bash scripts/verify-r8-keeps.sh [APK]
#   APK defaults to apps/mobile/build/app/outputs/flutter-apk/app-release.apk
#   Build one first:  cd apps/mobile && flutter build apk --release
#
# Exit: 0 = all required classes present   1 = something was stripped
#       2 = apk missing / unreadable
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
APK="${1:-$ROOT/apps/mobile/build/app/outputs/flutter-apk/app-release.apk}"

if [[ ! -f "$APK" ]]; then
  echo "verify-r8-keeps: no APK at $APK" >&2
  echo "Build one:  cd apps/mobile && flutter build apk --release" >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
unzip -q -o "$APK" 'classes*.dex' -d "$WORK" || { echo "verify-r8-keeps: no dex in $APK" >&2; exit 2; }

# Descriptors that must survive minification, with their original names.
REQUIRED=(
  "Lbiz/cunning/cunning_document_scanner/CunningDocumentScannerPlugin;"
  "Lbiz/cunning/cunning_document_scanner/ScannerArguments;"
  "Lbiz/cunning/cunning_document_scanner/fallback/DocumentScannerActivity;"
  "Lbiz/cunning/cunning_document_scanner/fallback/DocumentScannerFileProvider;"
  "Lcom/google/mlkit/vision/documentscanner/GmsDocumentScanning;"
  "Lcom/google/mlkit/vision/documentscanner/GmsDocumentScanningResult;"
  "Lcom/google/mlkit/vision/documentscanner/GmsDocumentScannerOptions;"
)

echo "== verify-r8-keeps =="
echo "  apk: $APK"

ALL_STRINGS="$WORK/all.strings"
: > "$ALL_STRINGS"
for dex in "$WORK"/classes*.dex; do
  strings "$dex" >> "$ALL_STRINGS"
done

missing=0
for descriptor in "${REQUIRED[@]}"; do
  if grep -qF "$descriptor" "$ALL_STRINGS"; then
    echo "  ok      $descriptor"
  else
    echo "  MISSING $descriptor"
    missing=$((missing + 1))
  fi
done

if [[ $missing -gt 0 ]]; then
  echo
  echo "FAIL: R8 stripped $missing class(es) the document scanner needs."
  echo "The app will build and pass tests, and the REAL scanner will be broken."
  echo "Fix: restore the keep rules in apps/mobile/android/app/proguard-rules.pro"
  exit 1
fi

echo
echo "OK: the document-scanner classes survived R8."
