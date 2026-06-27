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
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Static criteria ----
# Tests assert the three widgets exist (home screen title, empty state, Scan button)
assert_cmd "a1 widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

# analyze clean
assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

# ---- Device criteria: launch via `nx run mobile:run` on each platform ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_android_run
verify_ios_run

verify_summary
