#!/usr/bin/env bash
# Combined HOST + E2E coverage — the figure worth gating on.
#
# Neither suite alone tells you whether code is tested:
#   * the host suite cannot touch native paths, platform views, or real device
#     storage;
#   * the e2e suite cannot inject faults, and a single device can only ever
#     reach one side of a Platform.isIOS fork.
# They are complementary, so a line is COVERED here if either suite reached it.
# Measured on this repo: host 91.6%, e2e 82.6%, combined 96.6%.
#
# Inputs (neither is produced by this script — run those first):
#   apps/mobile/coverage/lcov.info        bash scripts/coverage.sh
#   apps/mobile/coverage/e2e-merged.info  bash scripts/coverage-e2e.sh <device>
#                                         (run it on BOTH phones and it merges)
#
# Usage (from repo root):
#   bash scripts/coverage-combined.sh
#   bash scripts/coverage-combined.sh --gate 99
#
# Policy lives in scripts/coverage_policy.py, shared with the other two scripts
# so the three numbers stay comparable.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MOBILE="$REPO_ROOT/apps/mobile"

HOST="$MOBILE/coverage/lcov.info"
E2E="$MOBILE/coverage/e2e-merged.info"

GATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --gate) GATE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

missing=0
[ -f "$HOST" ] || { echo "missing $HOST — run: bash scripts/coverage.sh" >&2; missing=1; }
[ -f "$E2E" ]  || { echo "missing $E2E — run: bash scripts/coverage-e2e.sh <device-id>" >&2; missing=1; }
[ "$missing" = 0 ] || exit 2

python3 - "$REPO_ROOT" "$HOST" "$E2E" "$GATE" <<'PY'
import sys, os, collections
repo_root, host_path, e2e_path, gate = sys.argv[1:5]
sys.path.insert(0, os.path.join(repo_root, 'scripts'))
from coverage_policy import filtered_records  # noqa: E402


def load(path):
    hits = collections.defaultdict(dict)
    cur = None
    for line in open(path):
        line = line.strip()
        if line.startswith('SF:'):
            cur = line[3:]
        elif line.startswith('DA:') and cur:
            ln, cnt = line[3:].split(',')[:2]
            hits[cur][int(ln)] = hits[cur].get(int(ln), 0) + int(cnt)
        elif line == 'end_of_record':
            cur = None
    return hits


def norm(p):
    # host and e2e lcov spell the same file differently (absolute vs relative)
    return p.split('apps/mobile/')[-1].lstrip('./')


def totals(hits):
    recs = filtered_records(hits, repo_root)
    return sum(r[1] for r in recs), sum(r[2] for r in recs), recs


host = {norm(f): l for f, l in load(host_path).items()}
e2e = {norm(f): l for f, l in load(e2e_path).items()}

combined = collections.defaultdict(dict)
for src in (host, e2e):
    for f, lines in src.items():
        for ln, c in lines.items():
            combined[f][ln] = combined[f].get(ln, 0) + c

hh, hn, _ = totals(host)
eh, en, _ = totals(e2e)
ch, cn, recs = totals(combined)

print(f"  HOST only  {hh}/{hn} = {hh/hn*100:.2f}%")
print(f"  E2E only   {eh}/{en} = {eh/en*100:.2f}%")
print()

worst = sorted(recs, key=lambda r: r[2] - r[1], reverse=True)[:15]
print("Uncovered by BOTH suites:")
for f, h, l in worst:
    if l - h:
        print(f"  {l-h:>4} miss  {h/l*100:5.0f}%  {f.replace('lib/features/', '').replace('lib/', '')}")
print()
print(f"COMBINED COVERAGE: {ch}/{cn} = {ch/cn*100:.2f}%")

if gate:
    g = float(gate)
    if ch / cn * 100 < g:
        short = int(cn * g / 100 + 0.999) - ch
        print(f"GATE FAIL: {ch/cn*100:.2f}% < {g:.2f}%  (short by {short} lines)")
        sys.exit(1)
    print(f"GATE PASS: {ch/cn*100:.2f}% >= {g:.2f}%")
PY
