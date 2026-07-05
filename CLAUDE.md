# CamScanner-light — project notes for Claude

Flutter document scanner. App lives in `apps/mobile/`.

## Shipping a TestFlight / App Store build (iOS)

When asked to "prepare the next version on TestFlight" (or similar), do this:

1. **Bump the build number** in `apps/mobile/pubspec.yaml` — the `+N` suffix of
   `version: 1.0.0+N`. TestFlight **rejects a build number it has already seen**,
   so ask the user (or check App Store Connect) for the last uploaded build and
   increment it. Do not assume `pubspec` is in sync with TestFlight — it may lag.

2. **Build the Release IPA** from repo root:
   ```bash
   bash scripts/build-ios-release.sh
   ```
   This archives + does an app-store export via `apps/mobile/ios/ExportOptions.plist`
   (method `app-store-connect`, automatic signing, team `DGLKF29HPV`) and prints the
   output path and embedded version.
   Output: `apps/mobile/build/ios/ipa/mobile.ipa`.

3. **The user uploads it themselves** with `xcrun` (do not upload unless they ask):
   ```bash
   xcrun altool --upload-app -f apps/mobile/build/ios/ipa/mobile.ipa \
     -t ios --apiKey <KEY_ID> --apiIssuer <ISSUER_ID>
   # or:  -u <apple-id> -p <app-specific-password>
   ```
   `notarytool` is NOT needed — TestFlight/App Store uploads aren't notarized.

### Must ship RELEASE, never Debug
A **Debug** IPA crashes ~2–10ms into every cold launch on-device (VSyncClient
SIGSEGV — Dart JIT needs an attached debugger). Always `--release` (the script does this).

### Distribution signing is NOT persistent on this machine
The export step needs an **Apple Distribution** cert. This machine's keychain often
has only an *Apple Development* cert and reports "No Accounts", so the export fails
with `No signing certificate "iOS Distribution" found`. Fix: the user signs an Apple
ID (paid Developer Program, team `DGLKF29HPV`) into **Xcode → Settings → Accounts** —
automatic signing then mints the distribution cert/profile on demand. The provisioning
profiles already in `~/Library/MobileDevice/Provisioning Profiles/` are for a *different*
app (`lu.luxauto.v2`, team `KW4H5RPWBL`) and are expired — ignore them.
`flutter build ipa --release` alone still archives fine; only the *export* needs the account.

If export fails on signing, don't guess — tell the user to sign into Xcode, then re-run
just the export against the existing archive (no re-archive needed):
```bash
cd apps/mobile && xcodebuild -exportArchive \
  -archivePath build/ios/archive/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions.plist \
  -allowProvisioningUpdates
```

## Android release
`bash scripts/build-release.sh` — split-per-abi APKs + App Bundle, obfuscated,
symbols in `apps/mobile/build/symbols/`.
