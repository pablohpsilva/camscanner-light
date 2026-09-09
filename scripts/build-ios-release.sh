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

# The iOS Bitcoin section is now ALWAYS on, including in App Store builds.
# It used to be forced off here under Guideline 3.1.1; that kill switch is gone
# and DonationScreen.iosBtcDonation is an unconditional `true`. The section is
# display-only (a QR code and a copyable address, no in-app payment path) and
# still auto-hides when BITCOIN_ADDRESS is empty in donation_config.json.
# If Apple ever objects, the revert is to reinstate this define AND restore the
# build flag in donation_screen.dart -- the define alone no longer does anything.

echo "== building release IPA (archive + app-store export) =="
flutter build ipa --release \
  --export-options-plist="$APP/ios/ExportOptions.plist" \
  ${DEFINES[@]+"${DEFINES[@]}"} \
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
