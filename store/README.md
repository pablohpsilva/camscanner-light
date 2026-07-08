# Store listing screenshots

Appealing, on-brand App Store / Play Store screenshots for **ScannerCam Light**,
for four device classes. The finished images a user swipes through when
downloading the app live in [`final/`](final/).

| Class            | Canvas (px) | Sourced from                        |
|------------------|-------------|-------------------------------------|
| `ios-iphone`     | 1320 × 2868 | iPhone 16 Plus simulator (iOS 18.3) |
| `ios-ipad`       | 2048 × 2732 | iPad Pro 13-inch (M4) simulator     |
| `android-phone`  | 1080 × 2400 | Medium_Phone_API_35 emulator        |
| `android-tablet` | 1600 × 2560 | `store_tablet` AVD (Pixel Tablet, portrait) |

Each class has the same six screens, in listing order:

1. `01-scan` — Crisp scans in one tap
2. `02-library` — Your documents, organized
3. `03-filters` — Auto-enhance every page
4. `04-pdf` — Export polished PDFs
5. `05-search` — Find any word, instantly
6. `06-privacy` — 100% private

## Layout

```
store/
  raw/<class>/<screen>.png     # native device captures (source imagery)
  final/<class>/NN-<screen>.png # framed + captioned marketing images  <- deliverable
  template/frame.mjs           # HTML frame generator (gradient + bezel + caption)
  template/build.mjs           # raw -> final compositor (headless Chrome)
  template/fixtures.mjs        # generates the seed document images + store_fixtures.g.dart
  capture.sh                   # drives the app on a device and grabs raw screenshots
```

## How it's made (two stages)

**Stage A — capture** (`capture.sh` + `apps/mobile/integration_test/store_capture_test.dart`):
seeds a deterministic library (ACME invoice, Q2 report, café receipt — generated
by `fixtures.mjs`), drives the app into each of the six states, and grabs an
OS-level screenshot (`simctl` / `adb`) at each state. OS capture is used, not
`binding.takeScreenshot`, so native views — the pdfx PDF preview — render.

**Stage B — compose** (`build.mjs`): renders one HTML frame per screen with
headless Chrome at exact canvas size — on-brand gradient (indigo → `#2E7DFF`),
bold caption, and the raw screenshot inside a device bezel with a soft shadow.

## Regenerate

```bash
# 1. (once) regenerate seed document images + the Dart fixture file
node store/template/fixtures.mjs

# 2. capture raw shots on each device (boot the sim/emulator first)
store/capture.sh <iphone-udid>   ios-iphone     ios
store/capture.sh <ipad-udid>     ios-ipad       ios
store/capture.sh emulator-5554   android-phone  android
store/capture.sh emulator-5556   android-tablet android   # tablet forced to portrait: adb shell settings put system user_rotation 1

# 3. compose the final framed images
node store/template/build.mjs
```

Edit caption copy in `template/build.mjs` (`SCREENS`) and re-run step 3 — the
frames regenerate instantly without re-capturing.

## Notes

- iOS 26 simulators are arm64-only; the app's build settings force x86_64 for the
  simulator (opencv_dart), so capture uses **iOS 18.x** sims.
- Raws already include the real device status bar, so the frame draws no faux
  notch/island.
