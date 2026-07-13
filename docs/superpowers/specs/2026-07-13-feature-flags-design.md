# Build-Time Feature Flags — Design

**Date:** 2026-07-13
**Status:** Approved (design), pending implementation plan
**Related:** existing build-time config `donation_config.dart` / `feedback_config.dart`
(`String.fromEnvironment` + `--dart-define-from-file` in `scripts/build-release.sh`)

## Goal

Let a build enable or disable each user-facing capability of the app through a
build-time environment variable, so white-label / store variants can strip any
feature without code changes. Every feature defaults **on** except **fax**,
which defaults **off**. A disabled feature's control is **hidden entirely** —
the user never sees it.

## Chosen approach

**A single injectable `FeatureFlags` config class**, one `bool` field per
capability, each defaulting from `const bool.fromEnvironment('FEATURE_X', …)`,
threaded through `LibraryDependencies` exactly as `FeedbackConfig` is threaded
through `FeedbackDependencies`.

Considered and rejected:

- **Global static access** (`FeatureFlags.print` referenced directly in
  widgets): `bool.fromEnvironment` is a **compile-time constant**, so a global
  const cannot be varied at test runtime — it would be impossible to write a
  widget test asserting "print hidden when its flag is off". Injecting an
  instance (const default reads the env; tests pass an override) is what makes
  the project's TDD mandate satisfiable.
- **`Map<Feature, bool>`**: more DRY but less readable at call sites and breaks
  the per-field `fromEnvironment` idiom the codebase already uses.

## The flags

One `bool` field per capability. Env var names are `FEATURE_<SCREAMING_SNAKE>`.
All `defaultValue: true` **except `FEATURE_FAX`**, which is `defaultValue: false`.

| Field (Dart) | Env var | Default | Gated control (key) |
| --- | --- | --- | --- |
| `crop` | `FEATURE_CROP` | true | toolbar `page-viewer-edit` |
| `rotate` | `FEATURE_ROTATE` | true | toolbar `page-viewer-rotate` |
| `filter` | `FEATURE_FILTER` | true | toolbar `page-viewer-filter` |
| `viewText` | `FEATURE_VIEW_TEXT` | true | toolbar `page-viewer-view-text` |
| `retake` | `FEATURE_RETAKE` | true | toolbar `page-viewer-retake` |
| `share` | `FEATURE_SHARE` | true | toolbar `page-viewer-share` (umbrella) |
| `deletePage` | `FEATURE_DELETE_PAGE` | true | toolbar `page-viewer-delete-page` |
| `rename` | `FEATURE_RENAME` | true | overflow `page-viewer-rename` |
| `merge` | `FEATURE_MERGE` | true | overflow `page-viewer-merge` |
| `split` | `FEATURE_SPLIT` | true | overflow `page-viewer-split` |
| `deleteDocument` | `FEATURE_DELETE_DOCUMENT` | true | overflow `page-viewer-delete` |
| `exportPdf` | `FEATURE_EXPORT_PDF` | true | share sheet `page-viewer-export` |
| `shareImage` | `FEATURE_SHARE_IMAGE` | true | share sheet `page-viewer-export-image` |
| `exportAllImages` | `FEATURE_EXPORT_ALL_IMAGES` | true | share sheet `page-viewer-export-all-images` |
| `print` | `FEATURE_PRINT` | true | share sheet `page-viewer-print` |
| `protectWithPassword` | `FEATURE_PROTECT_WITH_PASSWORD` | true | share sheet `page-viewer-protect` |
| `shareLink` | `FEATURE_SHARE_LINK` | true | share sheet `page-viewer-share-link` |
| `fax` | `FEATURE_FAX` | **false** | share sheet `page-viewer-fax` |
| `idCard` | `FEATURE_ID_CARD` | true | home `home-scan-id` |
| `scan` | `FEATURE_SCAN` | true | home `home-scan` |
| `import` | `FEATURE_IMPORT` | true | home `home-import` |

```dart
class FeatureFlags {
  final bool crop;
  // … one field per row above …
  final bool import;

  const FeatureFlags({
    this.crop = const bool.fromEnvironment('FEATURE_CROP', defaultValue: true),
    // … all others defaultValue: true …
    this.fax = const bool.fromEnvironment('FEATURE_FAX', defaultValue: false),
    // … remaining defaultValue: true …
  });
}
```

## Architecture

### Threading

- Add `final FeatureFlags features;` to `LibraryDependencies`, const default
  `const FeatureFlags()`. No change to `runCamScannerApp`'s signature — it
  already accepts a `LibraryDependencies` override.
- `HomeScreen` already receives `libraryDependencies`; it reads
  `widget.libraryDependencies.features` for the home buttons and passes the
  `FeatureFlags` into the `PageViewerScreen` constructor.
- `PageViewerScreen` gains a `final FeatureFlags features;` constructor field
  (defaulted to `const FeatureFlags()` so existing call sites/tests that don't
  care compile unchanged), read wherever it builds toolbar / overflow / share.
- Tests inject overrides: `LibraryDependencies(features: FeatureFlags(print: false))`,
  or construct `PageViewerScreen(features: FeatureFlags(print: false), …)` directly.

### Gating rules (hide entirely)

- **Bottom toolbar** (crop, rotate, filter, viewText, retake, share, deletePage):
  build only the enabled buttons into the `Expanded` row so it reflows to the
  remaining buttons. `EditorToolbar` receives the `FeatureFlags` (or per-action
  booleans) and conditionally includes each `Expanded` child.
- **Share bottom sheet** (exportPdf, shareImage, exportAllImages, print,
  protectWithPassword, shareLink, fax): build only the enabled tiles.
- **Share toolbar button** (`page-viewer-share`): shown iff
  `share == true` **AND at least one** of the seven share sub-flags is `true`.
  This guarantees an empty share sheet can never be opened. Turning off the
  umbrella `share` hides the button regardless of sub-flags.
- **Overflow menu** (rename, merge, split, deleteDocument): build only the
  enabled `PopupMenuItem`s; **hide the overflow button** (`page-viewer-page-menu`)
  entirely when all four are off.
- **Home buttons** (scan, idCard, import): build each `ReamActionButton` only
  when its flag is on.

## Error handling / accepted gaps

- Flags are compile-time constants; there is nothing to validate at runtime.
- A build **can** disable both `scan` and `import`, leaving no way to add
  documents. This is the operator's explicit choice under the "a build can
  strip anything" decision — documented here, not guarded.
- Disabling `fax` / `shareLink` merely hides controls that today already
  surface "not available yet" (their providers are `Unavailable*` stubs), so
  those flags are the cleanest way to remove the placeholders from a build.

## Testing

TDD + BDD. Note: this feature is **pure-Dart UI gating** — no camera, opencv,
ML Kit, drift-native, PDF, or share/print native path is exercised by the flag
logic itself. Host widget tests are therefore authoritative for the gating;
the device run is a smoke check, not a per-flag matrix (see below).

**Unit:**
- `FeatureFlags()` with no `--dart-define`: every field `true` **except `fax`**,
  which is `false`.
- A `FeatureFlags(print: false)` override leaves all other fields `true`.

**Widget (host — core coverage):**
- For each gated control: inject a `FeatureFlags` with that one flag `false`;
  assert its key finds **nothing**. With the default flags, assert its key
  finds **one** widget.
- Auto-hide rules:
  - `share == true` but all seven sub-flags `false` → `page-viewer-share`
    absent.
  - `share == true` with at least one sub-flag `true` → `page-viewer-share`
    present, and only the enabled tiles appear in the opened sheet.
  - all of rename/merge/split/deleteDocument `false` → `page-viewer-page-menu`
    absent.
- Toolbar reflow: with several toolbar flags off, only the enabled buttons are
  present and no overflow/exception occurs.

**BDD:**
- A `.feature` scenario — e.g. "a build with the print feature disabled hides
  the print action" — drives the app with an injected disabled flag via the
  dependency override, steps in `test/step/`, generated with `build_runner`.

**Device (Android + iOS) — smoke check:**
- A default release build still shows every feature (no regression from the
  gating refactor). The gating logic has no native dependency, so a per-flag
  on-device matrix is unnecessary; this is stated explicitly rather than
  claiming a device-verified matrix that adds no coverage.

## Global constraints

- Env var names are exactly `FEATURE_<SCREAMING_SNAKE>` as tabled above.
- All defaults `true` **except `FEATURE_FAX` = false**.
- Disabled ⇒ control **hidden entirely** (never greyed/disabled).
- `FeatureFlags` is **injectable** (const default reads `bool.fromEnvironment`;
  overridable in tests) — never referenced as a bare global const in widgets.
- Thread through `LibraryDependencies.features`; do not add a new top-level
  parameter to `runCamScannerApp`.
- Nothing is "done" until TDD + BDD are green on host, plus a default-build
  device smoke check on a real Android device AND a real iOS device.
