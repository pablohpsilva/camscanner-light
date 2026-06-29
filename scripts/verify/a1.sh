#!/usr/bin/env bash
# Verify A1 (app shell — Documents home screen) acceptance criteria.
# Run from anywhere: bash scripts/verify/a1.sh
# Honors VERIFY_SKIP_DEVICE=1 to skip the (slow) device launches — but skipping
# is itself reported, never silent. Exits non-zero if any criterion fails.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== A1 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Static criteria ----
# Tests assert the three widgets exist (home screen title, empty state, Scan button)
assert_cmd "a1 widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

# analyze clean
assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

# ---- Device criteria: programmatic on-device UI verification (integration test) ----
# Authoritative: runs the REAL app on each device and asserts the Documents home
# widget tree (a wrong/blank/splash UI fails). Supersedes screenshot evidence.
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android a1_home_screen_test.dart
verify_integration_ios a1_home_screen_test.dart

verify_summary
