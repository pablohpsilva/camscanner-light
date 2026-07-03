# K1 Task 4 Report

**Status:** DONE  
**Commit:** c2940cc  
**Summary:** BDD scenario, step def, generated test, device test, verify script, and plans-index row committed for K1 (rotate a page 90°).

## Generated test imports (from `integration_test/k1_rotate_page_test.dart`)

New step:
```
import './../test/step/i_rotate_the_page.dart';
```

Reused steps:
```
import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_capture_and_accept_the_first_page.dart';
import './../test/step/i_tap_done.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_see_the_page_viewer.dart';
```

## Verify result

`flutter analyze --no-fatal-infos` → `No issues found!`

## On-device concerns for parent

1. **BDD scan flow** (`k1_rotate_page_test.dart`): uses the real camera path (I1's flow) — needs Samsung RZCY51D0T1K with camera available. The rotate tap hits the `page-viewer-page-menu` popup then `page-viewer-rotate` key; confirm those keys appear in the viewer after opening a real document.
2. **Device test** (`k1_rotate_page_device_test.dart`): deterministic Drift test — no camera needed, but runs on device (needs `integration_test` binding). Should be green on any device.
3. **Image-cache eviction**: `_rotatePage()` clears `PaintingBinding.instance.imageCache` before reloading — verify on-device that the rotated image actually renders (not the stale one).
