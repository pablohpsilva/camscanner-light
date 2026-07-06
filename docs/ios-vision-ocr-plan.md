# Plan: Replace ML Kit OCR with Apple Vision on iOS (app-size reduction)

Status: **proposal for review — no code written yet.**
Owner: TBD. Worktree: `explore/app-size`.

## Why

`MLKitTextRecognitionCommon` is a **58 MB** static framework whose bulk is the
embedded Latin OCR *model data* — App Store thinning and dead-strip **cannot**
remove it, because it is data, not code. With the surrounding MLKit/Google
support pods it is the single largest contributor to the iOS download, ~60–66 MB.

iOS ships `Vision.VNRecognizeTextRequest` — a high-quality, on-device Latin text
recognizer — **built into the OS at 0 MB added**. Moving iOS OCR to Vision lets
us drop `google_mlkit_text_recognition` (and its transitive MLKit/Google pods)
from the **iOS** build entirely, while keeping ML Kit for Android.

Estimated iOS download saving: **~60 MB** (confirm post-build with
`flutter build ipa --release --analyze-size`). No change to Android size.

> Cheap win landed on this branch: removing the bundled 0.8 MB icon from
> `pubspec.yaml` (both platforms). The FFmpeg `.so` exclusion (−7.9 MB Android)
> was tried and **reverted** — on-device A/B proved libdartcv hard-links FFmpeg,
> so excluding it silently disables the native OpenCV pipeline (see memory
> `opencv-dart-ffmpeg-hard-linked`). This plan is the large, architectural step.

## The seam we build against (already exists — no redesign)

OCR is fully abstracted behind one interface; nothing else needs to change shape:

- `lib/features/library/ocr/ocr_engine.dart`
  `abstract interface class OcrEngine { Future<OcrResult> recognize(Uint8List jpegBytes); }`
- `lib/features/library/ocr/ocr_result.dart`
  `OcrResult { String text; List<OcrWordBox> words; }` where
  `OcrWordBox { String text; double left, top, right, bottom; }` — **normalized
  0..1, top-left origin**, `left/top` = top-left corner.
- Wiring: `library_dependencies.dart` → `ocrEngine: const MlKitOcrEngine()`.
- Consumers of the result: `drift_document_repository.dart` (persists
  `pages.ocrText` + `pages.ocrBoxes`, which feeds the **FTS5 `doc_fts` index**),
  `recognized_text_screen.dart`, `page_viewer_screen.dart` (word-box overlay),
  and the searchable-PDF text layer (`pdf/ocr_pdf_text_layer.dart`).

Because every consumer talks to `OcrResult`, the entire change is: **provide a
second `OcrEngine` implementation and pick it per platform.** No consumer edits
if we preserve the `OcrResult` contract exactly (text + normalized top-left word
boxes).

## Design

### 1. Platform-selected engine (DI)

Add a `PlatformOcrEngine` that delegates by platform, chosen in
`library_dependencies.dart`:

```
ocrEngine = Platform.isIOS ? const VisionOcrEngine() : const MlKitOcrEngine();
```

- `MlKitOcrEngine` stays exactly as-is for Android.
- `VisionOcrEngine` (new) implements `OcrEngine` and calls a Swift
  `MethodChannel` (`camscanner/vision_ocr`) with the JPEG bytes, receives a
  structured result, and maps it to `OcrResult`.

Keep the selection in the composition root only — consumers and tests still
inject their own fake `OcrEngine`, so host tests are unaffected.

### 2. Native iOS side (Swift, in `ios/Runner/`)

- New `VisionOcrPlugin.swift` registering a `MethodChannel`
  (`camscanner/vision_ocr`) in `AppDelegate`.
- Handler: decode the JPEG (`UIImage`/`CGImage`), run a
  `VNRecognizeTextRequest` with `recognitionLevel = .accurate`,
  `usesLanguageCorrection = true`.
- For each `VNRecognizedTextObservation`:
  - Take `topCandidates(1).first` → the line `string` and per-range
    `boundingBox(for:)` to derive **word-level** boxes (Vision is line-oriented;
    word boxes require splitting the candidate string into word ranges and
    querying each range's box). This is the main parity task.
  - Return a list of `{text, x, y, w, h}` normalized boxes + the full text.
- Return over the channel as a `Map`/`List` payload.

### 3. Coordinate mapping (the correctness-critical bit)

- **Vision uses a bottom-left origin, normalized 0..1**; the app's `OcrWordBox`
  uses **top-left origin, normalized 0..1**. Convert:
  `top = 1 - visionBox.maxY`, `bottom = 1 - visionBox.minY`,
  `left = visionBox.minX`, `right = visionBox.maxX`.
- Vision boxes are already normalized to the image, so no width/height division
  (unlike ML Kit, which returns pixel boxes we normalize in Dart).
- EXIF/orientation: the app feeds already-oriented JPEGs; pass
  `CGImagePropertyOrientation.up`. Verify against a rotated capture.

### 4. What we can delete once iOS no longer needs ML Kit

**SPIKE FINDING (verified against the pub cache):** `google_mlkit_text_recognition`
0.15.1 declares an **iOS `pluginClass`**, and its iOS podspec hard-depends on
`GoogleMLKit/TextRecognition ~> 9.0.0` (→ the 58 MB model) + `google_mlkit_commons`
→ `MLKitVision ~> 10.0.0`. So `pod install` pulls MLKit into the iOS build **as
long as the Dart plugin is a dependency at all** — not *calling* it on iOS does
NOT remove the pods. A Podfile `pre_install` hack deleting the pod target works
but is fragile across Flutter/CocoaPods versions.

**Clean resolution: drop the `google_mlkit_text_recognition` Dart plugin entirely
and make OCR fully native on BOTH platforms behind one MethodChannel**
(`camscanner/ocr`):
  - iOS → Swift `VNRecognizeTextRequest`.
  - Android → Kotlin calling the native `com.google.mlkit:text-recognition`
    Gradle artifact directly (same model, just from our plugin instead of the pub
    plugin).
This removes the pub plugin's iOS pods completely (real ~60 MB win) and keeps
Android OCR identical. Cost: we now own a small Kotlin OCR path for Android
(previously free from the plugin). Crux risk resolved — the saving is reachable,
priced at a native Android implementation.

## TDD + BDD test plan (per project NON-NEGOTIABLE — both platforms)

This feature is not "done" until all of the following are green. OCR is
native-only, so the seam is exercised on host via a fake and on-device for real.

**Host (TDD, run under `flutter test`):**
1. `VisionOcrEngine` maps a stubbed channel payload → `OcrResult` correctly:
   - bottom-left→top-left Y flip is correct (table of known boxes).
   - empty payload → `OcrResult.empty` (never throws for textless image).
   - malformed/absent fields degrade gracefully.
   Achieve by injecting a mock `MethodChannel` handler (`TestDefaultBinary
   MessengerBinding.defaultBinaryMessenger.setMockMethodCallHandler`).
2. `PlatformOcrEngine` selects Vision on iOS / ML Kit on Android
   (override `Platform` via an injected `isIOS` bool, not a global).
3. Existing OCR-consumer host tests (FTS indexing, recognized-text screen,
   PDF text layer) stay green using the fake `OcrEngine` — proves the contract
   is unchanged.

**BDD (`.feature` + generated test, steps in `test/step/`):**
4. Reuse/extend the existing OCR scenarios (`o1_ocr`, `o4_recognized_text`,
   `o5_content_search`) so the recognized-text + search behaviors are described
   independent of engine. No scenario should mention ML Kit or Vision by name.

**Device (integration_test, on a real device — REQUIRED for done):**
5. **iOS device**: `integration_test/o4_recognized_text_device_test.dart` (and
   OCR→PDF→search e2e) run against **Vision** on a real iPhone — recognizes a
   known fixture, boxes land on the right words, FTS search finds the doc.
6. **Android device**: the same device tests still pass against **ML Kit**
   (regression guard — we did not break Android).
   > Note (memory): the iOS **simulator** cannot link opencv_dart's arm64-sim
   > slice in 1.4.5, so iOS device tests must run on a **real** iPhone.

If a real iOS device is unavailable at implementation time, that is a **named
gap** to state explicitly — not a silent pass. Do not claim the size win without
`--analyze-size` output before/after.

## Rollout / sequencing

1. **Spike first (throwaway):** prove (a) `VNRecognizeTextRequest` quality on 3–5
   real document fixtures vs ML Kit, and (b) that excluding the MLKit pods from
   the iOS build is actually achievable and yields the ~60 MB. If (b) fails, stop
   — the win isn't real. Timebox.
2. Write host tests (red) → `VisionOcrEngine` + `PlatformOcrEngine` (green).
3. Swift `VisionOcrPlugin` + channel; wire DI.
4. Device-verify on real iPhone **and** real Android; capture `--analyze-size`
   before/after.
5. Update `CLAUDE.md` architecture note (OCR is now platform-split).

## Risks / open questions

- **Realizing the saving depends on dropping the iOS MLKit pods** — the spike
  must confirm this, or the code change saves ~0 MB. Highest risk.
- **Word-box parity**: Vision is line-oriented; per-word boxes need range
  queries. If overlay precision regresses, the word-box overlay
  (`page_viewer_screen`) and searchable-PDF layer are affected. Line-level boxes
  may be an acceptable fallback for search (text still indexes) but degrade the
  overlay — decide acceptable granularity.
- **Recognition-quality delta** vs ML Kit on real documents (spike measures).
- **Language scope**: Vision Latin is fine for parity; non-Latin was already not
  bundled in ML Kit here, so no regression.
- iOS min version: `VNRecognizeTextRequest` needs iOS 13+ — satisfied (deploy
  target 15.5).

## Measurement (definition of the win)

Before/after, from `apps/mobile/`:
```
flutter build ipa --release --analyze-size
```
Compare the per-framework breakdown; the win is the disappearance of
`MLKitTextRecognitionCommon` + `MLKit*`/`Google*` pods. Cross-check with the App
Store Connect "App Thinning Size Report" for the real download delta.
