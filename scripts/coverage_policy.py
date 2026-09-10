"""Shared coverage policy for scripts/coverage.sh and scripts/coverage-e2e.sh.

ONE definition of "what counts", so the host figure and the e2e figure can never
drift apart and quietly stop being comparable.

The denominator is hand-written Dart under lib/. Excluded:

  * generated files -- *.g.dart, *.freezed.dart, lib/l10n/gen/
  * Drift TABLE DSL -- the bodies of `class X extends Table`

That last one is the only judgement call, so here is the reasoning. A table is
pure declaration:

    class Documents extends Table {
      IntColumn get id => integer().autoIncrement()();
      TextColumn get name => text()();
    }

drift reads those getters at BUILD time and bakes the schema into
app_database.g.dart, which is already excluded as generated. At runtime the
getters are never called, so they can only ever be reported as missed -- 17
permanently-red lines in app_database.dart. A test that touched them would
assert nothing about behaviour; it would just move a number. Excluding the
declaration while KEEPING every hand-written line around it (openAppDatabase,
_createFts, the onUpgrade migration steps -- all real, all still counted) is the
same generated-code rationale already applied to *.g.dart.

Native-only files stay in the denominator: they are real code we simply cannot
reach from a host test, and hiding them would flatter the number.
"""

import os
import re

EXCLUDE_SUFFIXES = ('.g.dart', '.freezed.dart')
EXCLUDE_DIRS = ('lib/l10n/gen/',)

_TABLE_CLASS = re.compile(r'^\s*(?:abstract\s+)?class\s+\w+\s+extends\s+Table\b')


def is_excluded_file(path: str) -> bool:
    """True when the whole file is outside the denominator."""
    return (any(path.endswith(s) for s in EXCLUDE_SUFFIXES)
            or any(d in path for d in EXCLUDE_DIRS))


def drift_table_lines(path: str, repo_root: str) -> set:
    """1-based line numbers inside `class X extends Table { ... }` bodies.

    Brace-counted rather than indentation-guessed. Returns an empty set when the
    source cannot be read (a stale lcov path, say) so a missing file can never
    silently shrink the denominator.
    """
    candidates = [path]
    if not os.path.isabs(path):
        candidates.append(os.path.join(repo_root, path))
    candidates.append(os.path.join(repo_root, 'apps/mobile',
                                   path.split('apps/mobile/')[-1]))
    src = None
    for c in candidates:
        try:
            with open(c, encoding='utf-8') as fh:
                src = fh.readlines()
            break
        except (OSError, UnicodeDecodeError):
            continue
    if src is None:
        return set()

    out = set()
    active = False
    depth = 0
    seen_brace = False
    for i, line in enumerate(src, start=1):
        if not active and _TABLE_CLASS.match(line):
            active, depth, seen_brace = True, 0, False
        if not active:
            continue
        out.add(i)
        depth += line.count('{') - line.count('}')
        if '{' in line:
            seen_brace = True
        if seen_brace and depth <= 0:
            active = False
    return out


def filtered_records(hits: dict, repo_root: str):
    """(file, hit_lines, total_lines) per included file, policy applied.

    `hits` maps file path -> {line: exec_count}.
    """
    recs = []
    for path, lines in hits.items():
        if is_excluded_file(path):
            continue
        skip = drift_table_lines(path, repo_root) if 'drift/' in path else set()
        kept = {ln: c for ln, c in lines.items() if ln not in skip}
        if not kept:
            continue
        recs.append((path,
                     sum(1 for c in kept.values() if c > 0),
                     len(kept)))
    return recs
