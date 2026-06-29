#!/usr/bin/env bash
# Verify Step 0 (monorepo foundation) acceptance criteria.
# Run from anywhere: bash scripts/verify/step-0.sh
# Honors VERIFY_SKIP_DEVICE=1 to skip the (slow) device launches — but skipping
# is itself reported, never silent. Exits non-zero if any criterion fails.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== Step 0 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Static criteria ----
# Clean tree (check before anything that could dirty tracked files)
if [ -z "$(git status --porcelain)" ]; then
  pass "git working tree clean"
else
  fail "git working tree NOT clean"
fi

# analyze + test, cache disabled so a cached result can't mask a real run (rule 6)
assert_cmd "nx analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache
assert_cmd "nx test passes" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

# nx-flutter patch applied (proves the Node 24 fix survives install)
if grep -rqlF "existsSync" node_modules/@nxrocks/nx-flutter/src 2>/dev/null; then
  pass "nx-flutter patch applied (shim present in installed plugin)"
else
  fail "nx-flutter patch NOT applied (shim missing) [silence=fail]"
fi
# nx loads the patched plugin (would throw ERR_PACKAGE_PATH_NOT_EXPORTED otherwise)
assert_cmd "nx loads project (plugin OK)" '"name":"mobile"' \
  pnpm nx show project mobile

# ---- Device criteria: literal `nx run mobile:run` on each platform ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_android_run
verify_ios_run

verify_summary
