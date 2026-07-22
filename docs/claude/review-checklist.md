# CamScanner-light review checklist

Repo-specific traps to catch when reviewing changes to persistence, the native image pipeline, builds, or IAP. Distilled from hard-won project memory; when you learn a new repo-specific trap, add it here.

## Persistence (Drift + FTS5, DocumentFileStore)

- **Never persist ABSOLUTE image paths.** The iOS app-container GUID changes on reinstall, so any absolute path is dead after the next install. Store only RELATIVE paths in the DB; resolve against the container at read time.
- **Derive derivative/flat file names from the stored image PATH, not the live page POSITION.** Reordering pages changes position, so a position-based name silently collides across pages. Name flat/derivative files off the stored `relativeImagePath`.
- **Any schema change needs a `schemaVersion` bump AND an `onUpgrade` step.** The `doc_fts` trigram FTS5 vtable is built in raw SQL in `_createFts()` precisely so it runs from both `onCreate` and `onUpgrade` — forgetting the upgrade path leaves existing installs with a stale/missing index.
- **FTS5 indexes ONE row per document** (concatenated page OCR). This is what makes multi-word `MATCH`/AND work across pages — don't "fix" it to one row per page, that breaks cross-page AND queries.
- **Do NOT open the Drift DB on a spawned isolate** (`Isolate.spawn` / `createInBackground`). opencv 2.x made sqlite3 a native asset, so opening off the root isolate hangs — the classic "opens but never loads". Open the database on the root isolate.

## Native image pipeline (opencv_dart / compute isolate)

- **Native OpenCV OOM crashes the whole app UNCATCHABLY.** It's only safe today because the camera caps at ~12.5MP. Any change that raises input resolution or per-op memory must respect that bound — there is no catch that saves you.
- **Native work in a `compute` isolate MUST have a timeout.** A wedged native isolate can't be killed from Dart. The processor returns `null` on timeout so `FallbackPageProcessor` hands off to the pure-Dart path — don't remove the timeout or the fallback.
- **Beware DOUBLE EXIF orientation.** `img.decodeImage` auto-orients via EXIF, and Flutter itself honors EXIF Orientation on-device. Applying both rotates twice — decode-then-render already handles orientation.
- **Page edits are non-destructive and composable.** Crop/rotate/retake regenerate the flat from the pristine base via `_writeFlat`. Never write `relativeImagePath` inside an edit — that mutates the base and loses composability.

## Async / UI safety

- **A bare fire-and-forget `Future` must be `unawaited(...)` or awaited** — enforced by the `unawaited_futures` lint.
- **Clear loading flags in a `finally`.** Clearing only on the success path means a failure leaves the spinner forever — and `pumpAndSettle` then hangs on that perpetual spinner in tests.

## Builds / release (Android R8, iOS)

- **RELEASE-only breakage: R8/minify strips classes without keep rules.** The OS document scanner (`biz.cunning.**` from cunning_document_scanner) plus mlkit/gms/flutter/rainyl need keep+dontwarn rules. Scan device BDD uses FAKE scanners + DEBUG builds, so this is invisible to tests — smoke-test the REAL scanner on a RELEASE build before shipping.
- **Never ship a DEBUG iOS build.** It crashes ~2-10ms into cold launch (VSyncClient SIGSEGV — the JIT needs an attached debugger). Always build `--release`.
- **`flutter install` never builds.** It side-loads whatever is already in `build/` and can silently install a stale DEBUG app. Build first, then install; verify the artifact is Release (multi-MB `App.framework/App`, no `kernel_blob.bin`).

## IAP (iOS tip jar)

- **Silent StoreKit zero-products shows "tips unavailable" for everyone — no error, no crash.** Before assuming a code bug, verify: the three consumable products (`tip_small` / `tip_medium` / `tip_large`) are created AND submitted with the build in App Store Connect, and the Paid Applications Agreement is active (not lapsed/unsigned). Either gap yields zero products app-wide.

## Git hygiene

- **Never `git add -A` / `git add .`.** The working tree carries a long-lived multi-file uncommitted WIP pile that will contaminate a feature commit. Scope `git add` to named paths and verify with `git show <sha> --stat`.

## Verification discipline

- **"Passes on host" is NOT "device-verified."** Native-dependent behavior (camera, opencv, ML Kit, drift/sqlite, PDF, share/print, file I/O) must be proven on a real Android AND a real iOS device, or the gap named explicitly — never silently downgraded.
- **An empty `grep`/`rg` result is NOT proof of absence.** The rtk proxy hides some matches; confirm any load-bearing negative with `Read`.
