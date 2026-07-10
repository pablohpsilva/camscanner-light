# Revert ID capture to the OS document scanner — design

**Date:** 2026-07-10
**Status:** Approved for implementation
**Supersedes:** `2026-07-09-strict-single-shot-id-capture-design.md` (that feature was
built, merged, and then rejected on manual device testing — see below).

## Why

The strict single-shot ID capture feature (merged `952b7ab..e805f0f`) replaced the OS
document scanner in the ID flow with a plain `image_picker` camera + a manual crop/review
screen. On manual device testing the user rejected it: it lost the **live automatic
document detection + auto-crop** that the regular document-scan flow has. That auto-detection
comes from the OS document scanner (Apple VisionKit / Google ML Kit), which the single-shot
approach abandoned in order to force one-photo-per-side on iOS.

Decision (user, after testing both): **auto-detection matters more than iOS strict-one-shot.**
The two cannot coexist on iOS — VisionKit gives the detection but cannot be limited to one
photo and always ends on a "Save" tap. So we restore the OS scanner.

## What we build

A **full revert** of the single-shot feature, restoring the original OS-document-scanner ID
flow. Reverting previously-tested, known-good code is safer than authoring a third variant.

1. **`IdScanScreen` → OS document scanner per side.** Front: `scan(pageLimit: 1)` (Android
   locks to one auto-detected, auto-cropped page; iOS uses Apple's native scan+Save, first
   page taken) → **auto-advance** → back: same → save front as page 1, back as page 2 →
   `markAsIdCard`. No plain camera, no runtime permission prompt, no manual crop/review — the
   scanner's own detect-and-confirm IS the capture. **Save directly, no filter step** (user
   confirmed — fewest taps).
2. **`ScanScreen` in-document "Retake page" → OS scanner** (its original filter-only review),
   undoing the single-shot reroute.
3. **Remove all single-shot infrastructure** (now dead): `PhotoCamera` seam, `CameraPermission`
   seam, the `permission_handler` dependency, the iOS Podfile permission macros, the
   `CaptureReviewScreen` `title`/`acceptLabel`/`initialMode` params, and their tests/fakes.
   Restore the BDD `.feature` to the fake-scanner version.

## Mechanism

`git revert --no-commit 9b642c3..HEAD` (the 8 feature commits; the spec/plan docs at/ before
`9b642c3` are NOT in range and remain). This restores every touched file to its pre-feature
`9b642c3` state — equivalent to the exact original code. Resolve any trivial conflicts, verify
the touched files match `9b642c3`, commit as one revert, run the host suite, rebuild + reinstall
Release on both devices, push `master`.

## Result / trade-offs

- ID scan feels exactly like document scanning: point → auto-detect + crop → front → back → done.
- Android: locked to one auto-detected shot per side (strict + detected).
- iOS: Apple's native scan+Save per side (the multi-page UI the user originally disliked, now
  accepted as the price of auto-detection). We use the first scanned page per side.
- Removes the `permission_handler` dependency + iOS pod risk introduced by the reverted feature.

## Testing

- Host suite green (returns to the pre-feature baseline: the ID/scan tests revert to the
  fake-scanner versions). The 2 `opencv_edge_detector_test` failures remain the known
  environmental libdartcv host gap.
- Device: rebuild Release both platforms, reinstall; user manually verifies the ID flow now
  auto-detects like document scanning (front + back, 2-page ID card).
