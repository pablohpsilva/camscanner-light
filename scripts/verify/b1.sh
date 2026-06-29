#!/usr/bin/env bash
# Verify B1 (save photo + document record) acceptance criteria.
# Run: bash scripts/verify/b1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the real-camera + on-device privacy (EXIF) lane.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== B1 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "DocumentRepository interface exists" \
  "apps/mobile/lib/features/library/document_repository.dart" "abstract interface class DocumentRepository"
assert_file_has "DriftDocumentRepository is transactional" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "_db.transaction("
assert_file_has "image paths are relative" \
  "apps/mobile/lib/features/library/document_file_store.dart" "documents/\$docId/page_\$position.jpg"
assert_file_has "scrubber is byte-level (no package:image)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"
assert_file_has "SaveController exists" \
  "apps/mobile/lib/features/library/save_controller.dart" "class SaveController"
assert_file_has "documents list view exists" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "documents-list"
assert_file_has "EXIF test fixture present" \
  "apps/mobile/test/fixtures/exif_sample.jpg" ""  # presence only (non-empty)

# ---- Generated code is current (Drift + BDD) ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated drift/bdd diff" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/b1_save_document_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"
# NOTE: the marker '' on the line above means 'exit 0 only' — assert_cmd treats
# empty marker as 'no grep, just exit code'. (lib.sh: empty marker matches.)

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "b1 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration tests) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android b1_save_document_test.dart
verify_integration_ios b1_save_document_test.dart

# ---- Opt-in real-device lane: real camera -> saved, scrubbed JPEG on disk ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device connected"
  else
    apk="apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
    if ! ( cd apps/mobile && flutter build apk --debug ) >/dev/null 2>&1; then
      fail "REAL_DEVICE: debug APK build failed — skipping the rest of the lane"
    elif ! "$ADB" -s "$rdev" install -r -g "$apk" >/dev/null 2>&1; then
      fail "REAL_DEVICE: adb install -g failed — skipping the rest of the lane"
    else
      pass "REAL_DEVICE: installed with CAMERA pre-granted"
      "$ADB" -s "$rdev" shell pm grant "$APP_ID" android.permission.CAMERA 2>/dev/null
      "$ADB" -s "$rdev" shell svc power stayon true 2>/dev/null
      "$ADB" -s "$rdev" shell input keyevent KEYCODE_WAKEUP 2>/dev/null
      "$ADB" -s "$rdev" shell wm dismiss-keyguard 2>/dev/null
      # Negative control: clear prior saves so the assertion proves THIS run.
      "$ADB" -s "$rdev" shell "run-as $APP_ID find files -iname '*.jpg' -delete" 2>/dev/null
      "$ADB" -s "$rdev" shell am force-stop "$APP_ID" 2>/dev/null
      "$ADB" -s "$rdev" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 7
      size="$("$ADB" -s "$rdev" shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
      w="${size%x*}"; h="${size#*x}"
      # Open Scan (extended FAB ~83% x, ~88.8% y — measured SM-A166B), then
      # shutter (~50% x, ~86% y), then Accept (~83% x bottom-right of review).
      "$ADB" -s "$rdev" shell input tap "$(( w * 83 / 100 ))" "$(( h * 888 / 1000 ))" >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 6
      "$ADB" -s "$rdev" shell input tap "$(( w * 50 / 100 ))" "$(( h * 86 / 100 ))" >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 4   # takePicture + nav to review
      "$ADB" -s "$rdev" shell input tap "$(( w * 75 / 100 ))" "$(( h * 92 / 100 ))" >/dev/null 2>&1  # Accept
      "$ADB" -s "$rdev" shell sleep 5   # scrub + write + insert + nav home
      saved="$("$ADB" -s "$rdev" shell "run-as $APP_ID find files -path '*documents*' -iname '*.jpg' -size +0c" 2>/dev/null | tr -d '\r' | head -1)"
      if [ -n "$saved" ]; then
        pass "REAL_DEVICE: saved a non-empty JPEG under documents/ ($saved)"
        "$ADB" -s "$rdev" exec-out run-as "$APP_ID" cat "$saved" > "$EVIDENCE_DIR/b1-saved.jpg" 2>/dev/null
        # Privacy proof: a concrete EXIF reader (committed exif dev-dep) — no
        # missing-tool silent pass.
        if assert_cmd "REAL_DEVICE: saved JPEG has NO identifying EXIF" "EXIF_CLEAN" \
             bash -c "cd apps/mobile && dart run tool/exif_check.dart '$EVIDENCE_DIR/b1-saved.jpg' 2>&1"; then :; fi
      else
        fail "REAL_DEVICE: no saved JPEG under documents/ [silence=fail]"
      fi
      "$ADB" -s "$rdev" exec-out screencap -p > "$EVIDENCE_DIR/b1-real-home.png" 2>/dev/null
      "$ADB" -s "$rdev" shell svc power stayon false 2>/dev/null
    fi
  fi
  echo "REAL_DEVICE (iOS): MANUAL — confirm a saved document appears upright on a physical iPhone."
fi

verify_summary
