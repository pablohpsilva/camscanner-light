# Shipping a TestFlight / App Store build (iOS)

> Load this when asked to "prepare the next version on TestFlight" or ship to
> the App Store. Follow these steps — do not reproduce them from memory.

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

## In-App Purchase tip jar prerequisites (iOS)

The iOS tip jar (`tip_small`/`tip_medium`/`tip_large`) needs App Store Connect
setup that lives outside this repo — miss it and StoreKit silently returns
**zero products**, so the tip jar renders "tips unavailable" for every user
(no error, no crash — just empty).

- **Create all three consumable IAP products** (`tip_small`, `tip_medium`,
  `tip_large`) in App Store Connect and **submit them with the build** — new
  IAPs are reviewed alongside the app binary that first references them, not
  separately.
- **The Paid Applications Agreement must be active** in App Store Connect. If
  it lapses or was never signed, StoreKit returns zero products app-wide —
  same silent "tips unavailable" symptom, easy to misdiagnose as a code bug.
- **A sandbox tester account** is required to actually complete a purchase on
  a physical iPhone (production Apple IDs can't buy sandbox products).
- Before trusting a store build, run `flutter build ipa --release` **once**
  and confirm the `in_app_purchase` CocoaPod links cleanly — the pod is in
  `pubspec.yaml` but has never been archived on this branch. iOS IAP needs no
  extra entitlement or Xcode capability.
- Full detail: `docs/superpowers/specs/2026-07-18-ios-iap-tip-jar-design.md`.

## Must ship RELEASE, never Debug

A **Debug** IPA crashes ~2–10ms into every cold launch on-device (VSyncClient
SIGSEGV — Dart JIT needs an attached debugger). Always `--release` (the script does this).

## Distribution signing is NOT persistent on this machine

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
