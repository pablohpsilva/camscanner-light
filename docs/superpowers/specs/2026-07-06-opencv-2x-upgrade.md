# opencv_dart 1.4.5 → 2.1.0 upgrade

**Date:** 2026-07-06
**Status:** Implemented & verified (iOS device + Android emulator). Ready to merge.
**Branch/worktree:** `opencv-2x-upgrade`

## Why

Started as an attempt to unblock **iOS-simulator** integration testing: opencv_dart
1.4.5's `DartCvIOS` CocoaPods pod ships no arm64-simulator slice, so the app failed
to link for the Apple-Silicon simulator (`Framework 'DartCvIOS' not found`).

**Key discovery during the spike:** the iOS simulator is blocked by **more than
opencv** — `pdfx` (x86_64-sim only) and **MLKit** (`EXCLUDED_ARCHS[sim]=arm64`) also
lack arm64-simulator slices, and **Xcode 26 removed Rosetta** for the iOS simulator.
So **no iOS simulator can run this app on Apple Silicon regardless of opencv**;
iOS verification must use a **physical device** (all deps ship arm64-*device*).

The opencv 2.x upgrade was kept anyway as a **modernization** with concrete wins
(below), not because it fixes the simulator (it doesn't — MLKit/pdfx still block it).

## Decision: pin `opencv_dart: 2.1.0` exactly (NOT 2.2.x)

opencv_dart 2.x replaces the CocoaPods/AAR native packaging with **Dart Native
Assets** (build hooks in `dartcv4`). Within 2.x the build model differs by version:

- **2.1.0** — `dartcv4`'s CMake keeps `DARTCV_DISABLE_DOWNLOAD_OPENCV=OFF`: it
  **downloads prebuilt OpenCV** (`libopencv-ios/iossimulator/android-<arch>.tar.gz`)
  and compiles only the thin dartcv wrapper. **Clean iOS device build ≈ 51 s.**
- **2.2.x** — 2.2.0 flips the default to "build OpenCV from source" (full CMake
  compile). **Clean iOS build 258–441 s.** No prebuilt-download toggle is exposed
  via `user_defines`.

Both are **API-identical** for this app. So pin **exactly `2.1.0`** (not `^2.1.0`,
which resolves to the slow 2.2.x). This is the single most important detail of the
upgrade.

## Change-set

- `pubspec.yaml`
  - `opencv_dart: ^1.4.5` → `opencv_dart: 2.1.0` (exact)
  - Add native-assets module config:
    ```yaml
    hooks:
      user_defines:
        dartcv4:
          include_modules:
            - imgproc
            - imgcodecs
    ```
    (`core` is always on. The app's full opencv surface — perspective warp,
    filters, contours, decode/encode — lives in core+imgproc+imgcodecs. It uses
    NONE of calib3d/dnn/features2d/photo/stitching/objdetect/videoio.)
- `android/build.gradle.kts` — **remove** the `gradle.afterProject { … compileSdk = 36 }`
  block. Its rationale ("opencv_dart ships compileSdk 33 AAR") is void: 2.x has no
  Android AAR/JNI subproject (native assets). Verified: release APK builds without it.
- `android/app/proguard-rules.pro` — **remove** `-keep class dev.rainyl.** { *; }`
  and `-dontwarn dev.rainyl.**`. The old opencv_dart JNI loader classes don't exist
  under native assets. Verified: R8 release build succeeds without them.
- `pubspec.lock`, `ios/Podfile.lock` — regenerated (`DartCvIOS` pod gone).

**Zero Dart code changes.** `opencv_edge_detector.dart` and `native_page_processor.dart`
(the only two files importing `opencv_dart`, ~41 symbols) analyze clean on 2.1.0.

## Bonus win: FFmpeg dropped (~7.5 MB)

1.4.5's `libdartcv` hard-linked FFmpeg (`libav*`); it could not be stripped without
breaking the native load (see [[opencv-dart-ffmpeg-hard-linked]]). Under 2.x the
dartcv hook only links FFmpeg when `highgui`/`videoio` are included — which we
exclude. Verified: the iOS bundle's `dartcv.framework/dartcv` is a single **8.7 MB**
binary with **no `libav*`**.

## Verification matrix

| Check | iOS (physical iPhone 14 Pro Max, iOS 18.7.8) | Android (emulator-5554) |
|---|---|---|
| Dart analyze (2 opencv files) | ✅ clean | ✅ clean |
| Clean build speed | ✅ ~51 s (`--no-codesign`) | ✅ fast (prebuilt android tarball) |
| FTS BDD (`fts_search_device_test`) | ✅ pass | ✅ pass (pre-upgrade, opencv-independent) |
| Native pipeline `np1` (warp+enhance) | ✅ 3/3 | ✅ pass |
| Edge detection `f1` (segmentation/contours) | ✅ 6/6 | ✅ pass |
| Release APK (R8 minify, workarounds removed) | — | ✅ builds (`app-release.apk`) |
| Binary: FFmpeg dropped | ✅ 8.7 MB dartcv, no libav* | — |

## Caveats / follow-ups

- **iOS simulator remains unusable** on Apple Silicon + Xcode 26 (MLKit + pdfx lack
  arm64-sim; no Rosetta). Not an opencv issue. iOS testing = physical device. See
  [[ios-simulator-opencv-arm64-sim-missing]].
- Running **multiple** integration files in ONE `flutter test` invocation on a
  physical iOS device is flaky (per-file Dart-VM-service mDNS discovery drops → 60s+
  hangs / "Did not find a Dart VM Service"). Run device integration files as
  **separate invocations**.
- Android CLI builds require **Android Studio's Gradle daemon to be stopped**
  (it poisons CLI builds) — see [[android-studio-gradle-daemon-eperm]].
- `flutter build apk --release` universal APK is 136.7 MB (all ABIs); real ships use
  split-per-abi (`scripts/build-release.sh`). FFmpeg drop reduces per-abi size.
