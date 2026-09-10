#!/usr/bin/env bash
# Measure E2E (integration_test) line coverage on a REAL DEVICE.
#
# scripts/coverage.sh measures the HOST suite only — `flutter test --coverage`
# never runs integration_test/, so the ~91% it reports says nothing about e2e.
# This script fills that gap: it runs each integration_test file on a device
# with --coverage-path, then merges the per-test lcov files and reports the
# total under the SAME policy as coverage.sh (exclude generated code).
#
# Usage (from repo root):
#   bash scripts/coverage-e2e.sh <device-id>            # run all, merge, report
#   bash scripts/coverage-e2e.sh <device-id> --no-run   # re-report existing runs
#   bash scripts/coverage-e2e.sh <device-id> --gate 80  # non-zero exit below N%
#
# Per-test lcov lands in apps/mobile/coverage/e2e/<device-id>/<test>.info — one
# directory PER DEVICE, so two platforms never overwrite each other. The merge
# unions every device directory into apps/mobile/coverage/e2e-merged.info.
#
# NOTE ON PLATFORM BRANCHES: a single-device run can never cover both sides of a
# Platform.isIOS / donationsAvailable / tipJarAvailable fork — on Android the
# whole iOS tip jar reads as 0%. Run this on an Android device AND an iPhone;
# the merge then counts a line covered if EITHER platform reached it, which is
# worth several points. `--no-run` re-reports whatever is already on disk.
#
# NOTE ON COST: this installs and launches the app once per test file. Expect
# tens of minutes. It also leaves a DEBUG build on the device — reinstall the
# release/production build afterwards (see docs/claude/device-install.md).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
MOBILE="$REPO_ROOT/apps/mobile"
cd "$MOBILE"

DEVICE="${1:-}"
[ -n "$DEVICE" ] || { echo "usage: bash scripts/coverage-e2e.sh <device-id> [--no-run] [--gate N]" >&2; exit 2; }
shift

RUN=1
GATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-run) RUN=0; shift ;;
    --gate) GATE="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

# Per-device subdirectory. Every device MUST have its own, or a second run
# overwrites the first device's per-test files and the "merge both platforms"
# promise above silently becomes "whichever ran last".
SAFE_DEVICE="$(printf '%s' "$DEVICE" | tr -c 'A-Za-z0-9._-' '_')"
ROOT_OUT="$MOBILE/coverage/e2e"
OUT="$ROOT_OUT/$SAFE_DEVICE"
mkdir -p "$OUT"

if [ "$RUN" = 1 ]; then
  FAILED=()
  for f in integration_test/*_test.dart; do
    name="$(basename "$f" .dart)"
    printf '== %-46s ' "$name"
    if flutter test "$f" -d "$DEVICE" \
         --coverage --coverage-path="$OUT/$name.info" >"$OUT/$name.log" 2>&1; then
      echo "ok"
    else
      echo "FAIL (see $OUT/$name.log)"
      FAILED+=("$name")
    fi
  done
  if [ ${#FAILED[@]} -gt 0 ]; then
    echo
    echo "!! ${#FAILED[@]} test file(s) failed — their lines are MISSING from the total below:"
    printf '   %s\n' "${FAILED[@]}"
    echo "   A failing e2e test understates coverage; fix these before trusting the number."
  fi
fi

ls "$ROOT_OUT"/*/*.info >/dev/null 2>&1 || { echo "no per-test lcov under $ROOT_OUT" >&2; exit 1; }

# Merge across ALL device subdirectories: a line covered on either platform
# counts, which is the only way Platform.isIOS forks can both be reached.
python3 - "$ROOT_OUT" "$MOBILE/coverage/e2e-merged.info" "$GATE" <<'PY'
import sys, glob, os, collections
out_dir, merged_path, gate = sys.argv[1], sys.argv[2], sys.argv[3]

EXCLUDE = ('.g.dart', '.freezed.dart')
EXCLUDE_DIRS = ('lib/l10n/gen/',)

# line-level union across every per-test lcov: a line is covered if ANY test hit it
hits = collections.defaultdict(dict)   # file -> {line: count}
for path in glob.glob(os.path.join(out_dir, '*', '*.info')):
    cur = None
    for line in open(path):
        line = line.strip()
        if line.startswith('SF:'):
            cur = line[3:]
        elif line.startswith('DA:') and cur:
            ln, cnt = line[3:].split(',')[:2]
            ln, cnt = int(ln), int(cnt)
            hits[cur][ln] = hits[cur].get(ln, 0) + cnt
        elif line == 'end_of_record':
            cur = None

with open(merged_path, 'w') as fh:
    for f, lines in sorted(hits.items()):
        fh.write(f'SF:{f}\n')
        for ln in sorted(lines):
            fh.write(f'DA:{ln},{lines[ln]}\n')
        fh.write(f'LF:{len(lines)}\n')
        fh.write(f'LH:{sum(1 for c in lines.values() if c > 0)}\n')
        fh.write('end_of_record\n')

inc = [(f, sum(1 for c in l.values() if c > 0), len(l))
       for f, l in hits.items()
       if not any(f.endswith(x) for x in EXCLUDE)
       and not any(d in f for d in EXCLUDE_DIRS)]

tlh = sum(r[1] for r in inc); tlf = sum(r[2] for r in inc)
pct = tlh / tlf * 100 if tlf else 100.0

worst = sorted(inc, key=lambda r: (r[2] - r[1]), reverse=True)[:20]
print()
print("Least-covered hand-written files by MISSED e2e lines:")
for f, h, l in worst:
    if l - h == 0:
        continue
    print(f"  {l-h:>4} miss  {h/l*100:5.0f}%  {h}/{l}  {f.split('apps/mobile/')[-1]}")
print()
print(f"E2E COVERAGE (merged {len(glob.glob(os.path.join(out_dir,'*','*.info')))} runs across "
      f"{len([d for d in glob.glob(os.path.join(out_dir,'*')) if os.path.isdir(d)])} device(s), "
      f"excl {', '.join(EXCLUDE)}): {tlh}/{tlf} = {pct:.2f}%")
print(f"merged lcov -> {merged_path}")

if gate:
    g = float(gate)
    if pct < g:
        print(f"GATE FAIL: {pct:.2f}% < {g:.2f}%")
        sys.exit(1)
    print(f"GATE PASS: {pct:.2f}% >= {g:.2f}%")
PY
