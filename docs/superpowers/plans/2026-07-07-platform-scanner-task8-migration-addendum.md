# Task 8 Migration Addendum — camera deletion + BDD migration

Replaces the original plan's single "Task 8" (which under-scoped the test blast
radius). Discovered during execution: deleting the custom camera breaks ~25 of
37 BDD `.feature` suites (many used camera-capture only to seed a document) and
removes gallery import's only entry point. User decisions:
- Strategy: **delete camera; retire camera-only scenarios; re-seed the rest** (not a full ScanScreen-drive migration).
- Gallery import entry point: **Home screen 'Import' action**.

Everything else (design, plugin, filter-per-batch) is unchanged from
`2026-07-07-platform-document-scanner-design.md`. Global Constraints from the
main plan still apply (run from `apps/mobile/`; TDD; analyze zero-warning; no
blanket `dart format`; host review paths non-loadable; scoped `git add`).

## Per-feature disposition

**DELETE (camera-only behavior; scan→filter→save is covered by the new scanner
BDD in Task 10):**
- `a2_scan_permission`, `a3_capture_review`, `f2_auto_corners`, `f3_live_overlay`
- `b1_save_document` (save-via-shutter), `h1_add_pages` (add-pages-via-camera)
- Delete each `.feature`, its generated `*_test.dart`, and any step file used
  ONLY by these (verify each step's other users with grep before deleting).

**KEEP unchanged (build `CaptureReviewScreen` directly, no camera):**
- `g1_grayscale`, `g3_auto_color`, `g4_filter_picker`
  (step `the_review_screen_is_open_with_a_captured_image` — survives).

**MIGRATE to a seeded document (new helper below):**
- Single seeded doc: `c2_pdf_preview`, `d1_rename`, `d3_sort`, `i1_export_image`,
  `j1_export_all_images`, `k1_rotate_page`, `n1_print_document`,
  `p1_pdf_password`, `q1_compress_export`, `r1_share_document`, `e3_reedit`
- Multi-page seeded doc: `h5_multipage_pdf`, `m1_split_document`
- Two seeded docs: `l1_merge_documents`, `r4_share_documents_zip`
- App-launch only (empty storage, no camera): `s1_donation_banner`

**ROUTE via the new Home Import action (gallery path keeps crop+filter):**
- `e1_crop` (drag a corner), `e2_flatten`, `i2_gallery_import`

## New seed helper (writes a real page image)

The existing `a_document_was_saved_to_persistent_storage_earlier` writes a DB row
but NO image file, so image-reading features (rotate/export/pdf/print/share)
would fail. Add a variant that writes real bytes:

- New step `a document with a real page image was saved to persistent storage earlier`
  (file `test/step/a_document_with_a_real_page_image_was_saved_to_persistent_storage_earlier.dart`):
  same as the existing seed step BUT also write `kFakeJpegBytes` (from
  `fake_scan.dart`) to the page's `relativeImagePath` resolved under
  `persistentDir` (mirror the app's `DocumentFileStore` layout — check
  `persistent_storage.dart` / `DocumentFileStore` for the exact base dir join),
  and insert `flatRelativePath` = same file so the viewer has an image.
- For multi-page: a `...with N real page images...` variant (loop positions).
- For two docs: call the single-doc seeder twice (distinct dirs/ids) or add a
  `two documents ... were saved` variant.
- Launch with the existing `the app launches reading that same storage`
  (it uses `grantedScanDependencies()` — that helper MUST keep working after
  Task 8.3 rewrites it; see 8.3).

Where a migrated `.feature` currently says:
```
Given the app is launched with camera permission granted and empty storage
When I tap the Scan button
And I capture and accept the first page   (or: And I tap the shutter)
```
replace with:
```
Given a document with a real page image was saved to persistent storage earlier
When the app launches reading that same storage
And I open the first document           (only if the feature then needs the viewer)
```
Keep each feature's remaining, feature-specific steps unchanged.

## Home Import action (Task 8.1)

Gallery import moves from the (deleted) camera app bar to Home.

- `HomeScreen`: add an app-bar `IconButton` key `home-import`
  (`Icons.photo_library_outlined`, tooltip "Import from gallery") that runs:
  pick via `dependencies.createGalleryPicker().pick()`; if non-null push
  `CaptureReviewScreen(image:, enableCrop: true, edgeDetector: dependencies.createEdgeDetector(), saving:, onRetake:, onAccept:)`;
  on accept `repository.createFromCapture(image, corners:, enhancer:)` then
  `_refresh()`. On pick-cancel do nothing; on error show a SnackBar
  ("Couldn't import photo").
- Reuse a `SaveController` or call the repository directly, matching how the old
  camera `_onImport`/`_onAccept` created a document (see the deleted
  `camera_screen.dart` history at commit before Task 8.3 for the exact save
  shape: create-new-document path).
- New step `i tap the import button` taps `Key('home-import')`; update
  `i_import_a_photo_from_the_gallery` to tap `home-import` (not `camera-import`).

## Sub-task sequence (each ends green: analyze clean + suites pass except the
## documented environmental `opencv_edge_detector_test.dart` host failures)

- **Task 8.1 — Home Import action.** TDD widget test (fake gallery picker →
  review appears → accept → `createFromCapture` called; cancel → no-op). Wire
  gallery picker + edge detector from `ScanDependencies` (home already holds
  `dependencies`). Camera code still present. Commit.
- **Task 8.2 — BDD migration.** Add the seed-with-image step(s); migrate the
  MIGRATE-group features; route e1/e2/i2 through the Home Import action; delete
  the DELETE-group features + their generated tests + camera-exclusive steps;
  keep g1/g3/g4. `dart run build_runner build --delete-conflicting-outputs`.
  Run `flutter test integration_test/` (widget mode) green. Camera LIB still
  present (nothing in BDD drives it now). Commit.
- **Task 8.3 — Delete camera lib + host tests + DI/fake rewrite.** Delete the
  camera/live lib files and their `test/features/scan/camera_*` host tests; trim
  `detectFrame`/`_segmentGrayFrame` + `frame_reducer`/`gray_frame`/`camera_frame`
  from the detector; remove `createPermissionService`/`createPreviewController`
  from `ScanDependencies`; rewrite `fake_scan.dart` (drop camera/permission/
  preview fakes and their helpers; **rewrite `grantedScanDependencies()` to
  return `ScanDependencies(createDocumentScanner: () => FakeDocumentScannerService(const []))`**
  so surviving seed/launch steps keep compiling; keep `FakeEdgeDetector` (detect
  only), `FakeGalleryPicker`, `FakeDocumentScannerService`,
  `HangingDocumentScannerService`, `kFakeJpegBytes`); fix surviving non-BDD tests
  that used removed helpers (`donation_banner_wiring_test`, `home_screen_test`,
  `home_search_test`, `page_viewer_h4_test`). `flutter analyze` whole app clean;
  full host suite green except the documented opencv env failures. Commit.

Then the original plan resumes: Task 9 (drop deps), Task 10 (new scanner BDD),
Task 11 (device verification).
</content>
