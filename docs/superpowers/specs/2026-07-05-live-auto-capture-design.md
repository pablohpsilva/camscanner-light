# Live Auto-Capture (Feature A)

**Date:** 2026-07-05
**Status:** Design approved, pending implementation plan
**Feature group:** Auto-crop (B → A → C). B (faster live detection) is merged; this spec
covers **A only** — automatically firing the shutter when a detected document is held
steady. C (warp application) is a separate spec.

## Problem

Capture is manual only: the user frames a document and taps the shutter. Every other
scanner app auto-fires once the page is steady and confidently detected, so the user can
just point. The live detection pipeline already produces a per-frame `DetectionResult`
(quad corners + confidence) and draws the overlay; nothing consumes it to trigger capture.

## Goal & non-goals

**Goal:** When auto-capture is enabled, fire the shutter automatically once the detected
document quad is held steady and confident for a short dwell, with a countdown ring for
feedback. The manual shutter always works. Default: auto-capture ON.

**Decisions (from brainstorming):**
- Trigger: **stable + confident** for a dwell (not confidence-only; no coverage/size gate).
- Feedback: **countdown ring**.
- Control: **toggle button**, manual shutter always available; **default ON**.
- Mechanism: **frame-count** dwell (not wall-clock).
- Post-capture: the **same review screen** as manual capture.

**Non-goals (YAGNI):**
- Coverage/size gate (document must fill N% of frame) — explicitly not chosen.
- Wall-clock dwell + injected clock seam — frame-count is used instead.
- Persisting the toggle across sessions (matches the non-persisted flash-mode pattern).
- Sound/haptics on fire; auto-*accept* (capture still goes to review).

**Success criteria:**
- With auto-capture on, holding a document steady for ~N detections fires the shutter and
  opens the review screen — verified in host widget/BDD tests via `emitFrame`.
- The countdown ring reflects stability progress and resets when the document moves or is lost.
- Turning the toggle off restores manual-only behavior; the manual shutter fires in both modes.
- The stability logic is fully host-tested in isolation.

## Why frame-count (not wall-clock)

Detection runs behind the 150ms sampling throttle (from Feature B) plus the `_isDetecting`
in-flight guard, so frames reach the tracker at a floored cadence. `requiredStableFrames = 6`
therefore guarantees a wall-time floor of ~0.9s of real "hold" without any clock. This also
makes the logic trivially host-testable: each emitted frame advances the counter
deterministically, with **no Stopwatch/clock to inject** (Stopwatch does not play well with
widget-test fake time).

## Components

### New

**`lib/features/scan/auto_capture_controller.dart` — `AutoCaptureController` + `AutoCaptureState`**

Pure Dart (no camera/OpenCV) — host-testable. Consumes one detection result per frame,
tracks consecutive stability, reports progress and a one-shot fire signal.

```dart
class AutoCaptureState {
  final double progress;   // [0..1] = stableCount / requiredStableFrames
  final bool shouldFire;   // true on the frame the dwell is first met
  const AutoCaptureState({required this.progress, required this.shouldFire});
}

class AutoCaptureController {
  final int requiredStableFrames;   // default 6
  final double maxCornerDelta;      // default 0.02 (normalized [0..1] coords)
  final double minConfidence;       // default 0.6

  AutoCaptureState update(DetectionResult? result);
  void reset();
}
```

`update` semantics:
- `result == null` OR `result.confidence < minConfidence` → set count = 0, clear the stored
  quad, return `progress: 0, shouldFire: false`.
- else compute the max per-corner displacement between `result.corners` and the stored quad
  (Euclidean distance per corner, in normalized coords):
  - no stored quad yet → count = 1 (first stable frame).
  - displacement ≤ `maxCornerDelta` → count += 1.
  - displacement > `maxCornerDelta` → count = 1 (this frame is the new baseline).
  - store `result.corners` as the new reference.
  - `shouldFire = count >= requiredStableFrames`; `progress = (count / requiredStableFrames)`
    clamped to `[0,1]`.
- Once `shouldFire` is returned, the controller does not fire again until `reset()` (the
  caller resets after acting). `reset()` sets count = 0 and clears the stored quad.

### Changed

**`lib/features/scan/camera_screen.dart`**
- New state: `bool _autoCaptureEnabled = true;` (default ON), `double _autoProgress = 0;`,
  and a `final AutoCaptureController _autoCapture = AutoCaptureController();`.
- In `_onFrame`, after the existing `setState(_liveResult = ...)`: if `_autoCaptureEnabled`,
  call `final s = _autoCapture.update(result);`. If `s.shouldFire`, call `_autoCapture.reset()`
  then trigger capture by invoking the existing `_onShutter()` (DRY — same stop→capture→
  review→resume flow). Otherwise `setState(() => _autoProgress = s.progress)`.
- `_stopSampling()` additionally calls `_autoCapture.reset()` and clears `_autoProgress` — this
  covers capture start, entering review, and dispose (sampling stops in all cases); toggle-off resets the tracker directly in `_onAutoCaptureToggled` without stopping the live overlay.
- New `_onAutoCaptureToggled()`: flips `_autoCaptureEnabled`; when turning off, resets the
  tracker and clears `_autoProgress`.
- Pass `autoCaptureEnabled`, `onAutoCaptureToggled`, `autoCaptureProgress` to
  `CameraPreviewView`.

**`lib/features/scan/widgets/camera_preview_view.dart`**
- New params: `bool autoCaptureEnabled`, `VoidCallback onAutoCaptureToggled`,
  `double autoCaptureProgress`.
- Auto-capture **toggle button** — mirrors the existing flash toggle; key
  `scan-auto-capture-toggle`; icon `Icons.motion_photos_auto` (on) / `Icons.motion_photos_paused`
  (off).
- **Countdown ring** — a `CircularProgressIndicator(value: autoCaptureProgress)` around the
  shutter button, shown when `autoCaptureEnabled && autoCaptureProgress > 0`.

### Unchanged
`_onShutter`, `_reviewAndSave`, `_onAccept`, capture/review/save flow, `detectFrame`, the
live overlay, the flash toggle. Manual capture is untouched; auto-capture reuses it.

## Data flow

```
_onFrame → detectFrame(frame) → result
  ├─ setState(_liveResult = result.confidence>=0.5 ? result : null)   // overlay (unchanged)
  └─ if _autoCaptureEnabled:
       s = _autoCapture.update(result)
       s.shouldFire ? (_autoCapture.reset(); _onShutter())            // auto-fire
                    : setState(_autoProgress = s.progress)            // ring
```

## Error handling / edge cases

- Auto-fire cannot run while `_onFrame` bails early (`_isDetecting`, `_controller.capturing`,
  not `ready`) — reuses existing guards. `_onShutter` stops sampling immediately, and the
  tracker is reset before firing, so there is no double-fire.
- Returning from review with the same document still in frame re-arms and fires again after
  ~N stable frames — **intended** for multi-page scanning (the user moves to the next page).
- Toggle state is per-session (not persisted), matching flash mode.

## Testing

**`AutoCaptureController` host tests (pure — the bulk):**
- null result and below-`minConfidence` result → progress 0, no fire, count reset.
- N consecutive stable high-confidence frames → `shouldFire` true on the Nth, `progress`
  reaches 1.0; earlier frames report the correct fractional progress (`count/N`).
- a mid-sequence displacement > `maxCornerDelta` restarts count to 1 (progress drops).
- displacement exactly at the threshold boundary is treated as stable (`<=`).
- confidence dropping below `minConfidence` mid-sequence resets.
- no re-fire on the frame after a fire without an intervening `reset()`.
- `reset()` clears count and stored quad.

**Widget/BDD (`camera_screen`) — using `FakeCameraPreviewController.emitFrame` + a
`FakeEdgeDetector` returning a fixed high-confidence `DetectionResult`:**
- auto ON (default): emit N stable frames (same corners each) with pumps → review screen is
  pushed (capture happened).
- auto OFF (toggle tapped): emit N frames → no capture; the manual shutter still fires.
- the countdown ring is present with non-zero progress after a few stable frames and absent
  when progress is 0.

(Note: the fake detector returns identical corners each frame, so every frame is "stable" —
the "movement resets" path is covered by the pure controller tests, not the widget tests.)

## Migration / blast radius

- **New:** `auto_capture_controller.dart` + its host tests; widget tests for the toggle/ring.
- **Changed:** `camera_screen.dart` (tracker wiring + toggle + reset in `_stopSampling`),
  `camera_preview_view.dart` (3 params + toggle button + ring).
- **No change** to the detector, controllers, capture/save pipeline, or the still path.

## Open questions / risks

- **Tuning:** `requiredStableFrames`, `maxCornerDelta`, `minConfidence` are best-guess defaults;
  they are single constants and will be validated on-device (RZCY51D0T1K) — too eager (fires
  while aiming) → raise `requiredStableFrames` or lower `maxCornerDelta`; too reluctant → the
  reverse. On-device tuning is a tracked follow-up, same bucket as B's fps verification.
- **No coverage gate (model A):** a small, distant, but steady and ≥0.6-confidence page can
  auto-fire. Accepted per the brainstorming decision; revisit only if it misfires in practice.
