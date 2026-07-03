# L1 Task 3 Report

**Status:** COMPLETE  
**Commit:** fbe2c5f  
**Summary:** BDD feature, two new step defs, generated test, deterministic on-device device test, verify script, plans-index row — committed.

## Generated test imports (confirming new + reused steps)

From `integration_test/l1_merge_documents_test.dart`:

```
import './../test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart';
import './../test/step/i_tap_the_scan_button.dart';
import './../test/step/i_capture_and_accept_the_first_page.dart';
import './../test/step/i_tap_done.dart';
import './../test/step/i_open_the_first_document.dart';
import './../test/step/i_merge_the_other_document.dart';   ← new
import './../test/step/i_see_two_page_thumbnails.dart';    ← new
```

## Analyze result

`flutter analyze --no-fatal-infos` → **No issues found.**

## Concerns for parent to verify on-device

1. **`i_merge_the_other_document` tap target**: uses `byWidgetPredicate` to find the first `ListTile` whose key contains `merge-picker-item-`. This relies on the picker listing at least one other document; given two scans are done before the merge step, this should be satisfied. Verify the picker actually renders before the tap (no async gap).

2. **`i_see_two_page_thumbnails`**: asserts `page-thumb-0` and `page-thumb-1` are both visible in the strip after the merge. Requires the `PageThumbnailStrip` to re-render with two items after `mergeInto` completes and `_load()` refreshes the page list.

3. **`i_open_the_first_document` tile key**: taps `document-tile-1`. With two documents created, the "first" in the UI (newest by `modifiedAt`) must actually be tile-1. Verify ordering matches the library sort on device.
