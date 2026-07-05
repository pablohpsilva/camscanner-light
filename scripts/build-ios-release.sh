#!/usr/bin/env bash
# Build a Release, App-Store-signed IPA for TestFlight / App Store upload.
#   - archives + exports in one step using ios/ExportOptions.plist
#     (method app-store-connect, automatic signing, team DGLKF29HPV)
#   - obfuscated with split debug info; symbol maps land in build/symbols/
#     (retain per release to de-symbolicate crash traces; dSYMs are uploaded
#      to App Store Connect via uploadSymbols=true in ExportOptions.plist)
#
# Prereq: an Apple ID with the paid Developer Program must be signed in under
#   Xcode -> Settings -> Accounts (so automatic signing can mint the
#   distribution cert/profile). CLI-only keychains have only a Development cert.
#
# Bump the build number in apps/mobile/pubspec.yaml (the +N suffix) before
# running -- TestFlight rejects a build number it has already seen.
#
# Usage (from repo root):  bash scripts/build-ios-release.sh
# Output IPA:              apps/mobile/build/ios/ipa/mobile.ipa
# Then upload it yourself, e.g.:
#   xcrun altool --upload-app -f apps/mobile/build/ios/ipa/mobile.ipa \
#     -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel)"
APP="$ROOT/apps/mobile"
SYMBOLS="$APP/build/symbols"

cd "$APP"

echo "== building release IPA (archive + app-store export) =="
flutter build ipa --release \
  --export-options-plist="$APP/ios/ExportOptions.plist" \
  --obfuscate --split-debug-info="$SYMBOLS"

IPA="$(ls "$APP"/build/ios/ipa/*.ipa 2>/dev/null | head -1)"
if [[ -z "$IPA" ]]; then
  echo "!! no IPA produced -- check signing (Xcode -> Settings -> Accounts)" >&2
  exit 1
fi

echo "== artifact =="
ls -lh "$IPA" | awk '{print $5, $9}'
echo "== embedded version =="
unzip -p "$IPA" "Payload/Runner.app/Info.plist" \
  | plutil -extract CFBundleShortVersionString raw - | sed 's/^/  CFBundleShortVersionString: /'
unzip -p "$IPA" "Payload/Runner.app/Info.plist" \
  | plutil -extract CFBundleVersion raw - | sed 's/^/  CFBundleVersion: /'
echo "== symbol maps (retain per release) =="
ls -1 "$SYMBOLS" 2>/dev/null | sed 's/^/  /'

echo "S1 iOS RELEASE IPA COMPLETE -> $IPA"
