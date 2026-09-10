#!/usr/bin/env bash
# Measure host test line coverage under the project policy:
#   denominator = hand-written Dart under lib/, EXCLUDING generated code
#   (*.g.dart, *.freezed.dart, lib/l10n/gen/). Native-only files stay in the denominator.
#
# Usage:
#   bash scripts/coverage.sh            # run full host suite, report filtered %
#   bash scripts/coverage.sh --no-run   # reuse existing coverage/lcov.info
#   bash scripts/coverage.sh --gate 90  # exit non-zero if filtered % < 90
#
# Runs from repo root or anywhere; always operates on apps/mobile.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MOBILE="$REPO_ROOT/apps/mobile"
cd "$MOBILE"

RUN=1
GATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-run) RUN=0; shift ;;
    --gate) GATE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

if [ "$RUN" = 1 ]; then
  # opencv_edge_detector_test needs libdartcv (absent on host) — 2 known
  # environmental failures. Don't let them abort the coverage collection.
  flutter test --coverage || true
fi

[ -f coverage/lcov.info ] || { echo "coverage/lcov.info missing" >&2; exit 1; }

python3 - "$REPO_ROOT" "$GATE" <<'PY'
import sys, os, collections
repo_root, gate = sys.argv[1], sys.argv[2]
sys.path.insert(0, os.path.join(repo_root, 'scripts'))
from coverage_policy import filtered_records  # noqa: E402

hits = collections.defaultdict(dict)
cur = None
for line in open('coverage/lcov.info'):
    line = line.strip()
    if line.startswith('SF:'):
        cur = line[3:]
    elif line.startswith('DA:') and cur:
        ln, cnt = line[3:].split(',')[:2]
        hits[cur][int(ln)] = hits[cur].get(int(ln), 0) + int(cnt)
    elif line == 'end_of_record':
        cur = None

inc = filtered_records(hits, repo_root)
tlh = sum(r[1] for r in inc); tlf = sum(r[2] for r in inc)
pct = tlh / tlf * 100 if tlf else 100.0

worst = sorted(inc, key=lambda r: (r[2] - r[1]), reverse=True)[:15]
print("Lowest-coverage hand-written files (policy applied):")
for f, h, l in worst:
    if l - h == 0:
        continue
    print(f"  {l-h:>4} miss  {h/l*100:5.0f}%  {h}/{l}  {f.split('apps/mobile/')[-1]}")
print()
print(f"FILTERED COVERAGE (see scripts/coverage_policy.py): {tlh}/{tlf} = {pct:.2f}%")
if gate:
    g = float(gate)
    if pct < g:
        print(f"GATE FAIL: {pct:.2f}% < {g:.2f}%")
        sys.exit(1)
    print(f"GATE PASS: {pct:.2f}% >= {g:.2f}%")
PY
