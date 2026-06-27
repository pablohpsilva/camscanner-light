#!/usr/bin/env bash
# Shared verification helpers — see docs/superpowers/VERIFICATION.md
#
# Principle: SILENCE IS FAILURE. A check passes only on an explicit positive
# match (exit code 0 AND the expected marker present). Missing tool, missing
# marker, empty output, or non-zero exit => FAIL. No silent skips.

set -uo pipefail

ROOT="$(git rev-parse --show-toplevel)"
EVIDENCE_DIR="${EVIDENCE_DIR:-$ROOT/.superpowers/verify}"
mkdir -p "$EVIDENCE_DIR"

VERIFY_PASS=0
VERIFY_FAIL=0

_grn() { printf '\033[32m%s\033[0m\n' "$*"; }
_red() { printf '\033[31m%s\033[0m\n' "$*"; }

pass() { VERIFY_PASS=$((VERIFY_PASS + 1)); _grn "PASS: $*"; }
fail() { VERIFY_FAIL=$((VERIFY_FAIL + 1)); _red "FAIL: $*"; }

# require_tool <cmd> : a missing tool is a FAIL, never a skip (rule 4)
require_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    pass "tool present: $1"
    return 0
  fi
  fail "required tool MISSING: $1"
  return 1
}

_slug() { printf '%s' "$1" | tr ' /:' '___'; }

# assert_cmd "<desc>" "<expected-marker>" <command...>
# Runs the command, captures output+exit, asserts exit 0 AND marker present.
assert_cmd() {
  local desc="$1" marker="$2"; shift 2
  local log="$EVIDENCE_DIR/$(_slug "$desc").log" out rc
  out="$("$@" 2>&1)"; rc=$?
  printf '%s\n' "$out" >"$log"
  if [ "$rc" -ne 0 ]; then
    fail "$desc — exit $rc (see $log)"
    return 1
  fi
  if printf '%s' "$out" | grep -qF -- "$marker"; then
    pass "$desc — matched: $marker"
    return 0
  fi
  fail "$desc — marker NOT found: '$marker' [silence=fail] (see $log)"
  return 1
}

# assert_true "<desc>" <command...> : passes iff command exits 0
assert_true() {
  local desc="$1"; shift
  if "$@" >/dev/null 2>&1; then pass "$desc"; return 0; fi
  fail "$desc — command exited non-zero"
  return 1
}

# assert_file_has "<desc>" "<file>" "<marker>"
assert_file_has() {
  local desc="$1" file="$2" marker="$3"
  if [ -s "$file" ] && grep -qF -- "$marker" "$file"; then
    pass "$desc"; return 0
  fi
  fail "$desc — marker '$marker' not in $file [silence=fail]"
  return 1
}

# verify_summary : prints totals and exits non-zero if any check failed
verify_summary() {
  echo "------------------------------------------------"
  echo "VERIFY SUMMARY: ${VERIFY_PASS} passed, ${VERIFY_FAIL} failed"
  echo "Evidence: $EVIDENCE_DIR"
  if [ "$VERIFY_FAIL" -ne 0 ]; then _red "GATE: FAIL"; exit 1; fi
  _grn "GATE: PASS"; exit 0
}
