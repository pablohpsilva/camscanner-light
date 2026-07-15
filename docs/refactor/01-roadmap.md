# Refactor Roadmap — plan index, dependencies & parallelization waves

Companion to `00-overview-and-comparison.md`. This file says **what order to execute the 15 plans
in, what can run in parallel, and why**. Each plan is behaviour-preserving and self-contained; the
only hard sequencing root is **P00**.

---

## 1. Plan index

| ID | Plan | Tier | Effort | Risk | Depends on | Device verify |
|---|---|---|:--:|:--:|---|---|
| **P00** | Shared primitives (`AppLogger`, `withIsolateTimeout`, `TempFileWriter`) | 0 Foundation | S–M | Low | — | host |
| **P01** | Native pipeline OOM safety | 1 Safety | M | Med | — | Android+iOS |
| **P02** | Timeouts everywhere | 1 Safety | S–M | Low | P00 | both |
| **P03** | Persistence atomicity (merge/split txns) | 1 Safety | M | Med | — | both |
| **P04** | UI async-safety bugs | 1 Safety | S–M | Med | — | both |
| **P05** | Decompose the God repository | 2 SOLID | L | Med | (P10 first, soft) | both |
| **P06** | Extract view controllers from God widgets | 2 SOLID | L | Med | P00 | both |
| **P07** | Scan orchestration extraction | 2 SOLID | M | Med | — | both |
| **P08** | Native processor SOLID split + test seam | 2 SOLID | L | Med | P01 (same file) | Android+iOS |
| **P09** | Image-pipeline DRY & parity | 3 DRY | M–L | Med | (P08 soft) | both (parity) |
| **P10** | Repository DRY (helpers, temp-export, paths) | 3 DRY | S–M | Low | P00 | both |
| **P11** | Share-action model + flag gating | 3 DRY | M | Low | (P06 soft) | both |
| **P12** | Query & scaling (`_summaries`, N+1, sort) | 4 Perf | M | Low | — | host+both |
| **P13** | UI image memory & decoding | 4 Perf | M | Med | — | Android+iOS |
| **P14** | DI consistency, observability & 2°-feature cleanups | 3 Consistency | S–M | Low | P00 | both |
| **P15** | Hygiene: theme tokens, i18n date, lints, pins | 5 Hygiene | S–M | Low | — | host+both |

---

## 2. Dependency graph

```
P00 ──┬─▶ P02        (timeouts adopt withIsolateTimeout)
      ├─▶ P06        (runGuarded/AppLogger)
      ├─▶ P10        (TempFileWriter for _writeTempExport)
      └─▶ P14        (AppLogger sinks)

P01 ──▶ P08          (same file — do OOM hardening before/at the SOLID split)

soft edges (not blocking; reduce merge friction if ordered):
  P10 ─▶ P05   (extract repo helpers before splitting the class)
  P08 ─▶ P09   (split native file before sharing its math)
  P06 ─▶ P11   (controllers make the share-action wiring cleaner)

fully independent (no inbound edges): P03, P04, P07, P12, P13, P15
```

Only **P00** and **P01** are true prerequisites. Everything else is either independent or has a
*soft* edge that merely lowers rebase friction.

---

## 3. Parallelization waves

Run each wave's plans concurrently (independent files / no shared state); land + verify green
before starting the next. Within a plan, tasks fan out to further subagents.

**Wave A — foundation + independent safety (max fan-out)**
`P00` · `P01` · `P03` · `P04` · `P12` · `P15`
→ Ships the shared primitives, kills the OOM crash risk and the corruption risk, fixes the async
bugs, removes the home-load full-table scan, and clears hygiene — all touching disjoint files.

**Wave B — adopt primitives + structural extractions**
`P02` (needs P00) · `P06` (needs P00) · `P07` · `P08` (needs P01) · `P10` (needs P00) · `P13`
→ Timeouts adopted everywhere; the two God widgets and the native file get decomposed; scan
orchestration extracted; repo DRY helpers landed; viewer image memory bounded.

**Wave C — DRY on top of the new structure**
`P05` (smoother after P10) · `P09` (smoother after P08) · `P11` (smoother after P06) · `P14` (needs P00)
→ The big repository decomposition, the pipeline parity/DRY, the share-action model, and the DI
unification + observability sinks.

> Waves are guidance, not gates. A team with capacity can start any independent plan immediately;
> the waves just keep same-file plans from colliding (notably P01→P08→P09 on the native file, and
> P10→P05 on the repository).

---

## 4. Why this order

1. **Safety before structure.** The OOM float-copies (P01), non-atomic merge/split (P03), missing
   timeouts (P02), and the async bugs (P04) are the only items that can crash, corrupt, or hang the
   app in the field. They ship first, as small targeted fixes, *before* the large decompositions.
2. **Foundations enable de-duplication.** `AppLogger`/`withIsolateTimeout`/`TempFileWriter` (P00)
   are what let P02/P06/P10/P14 collapse the 32-way toast duplication, the 10 unguarded isolates,
   and the 7 temp-file sites without inventing the same helper five times.
3. **Cleanups before the big split.** Extracting the repo's `_requirePage`/`_cloneSourcePage`/
   `_writeTempExport` helpers (P10) shrinks the surface P05 then carves into collaborators.
4. **Same-file plans are serialized.** P01→P08→P09 all touch `native_page_processor.dart`; P10→P05
   both touch the repository. Ordering them avoids painful rebases while keeping every *other* plan
   parallel.

---

## 5. Executing a plan (the definition-of-done gate)

For each plan, per the project's non-negotiables:

1. Branch from `master` (worktree for isolation if running plans in parallel).
2. For each task: **write the failing test first** (unit/widget), watch it fail, implement the
   minimum, refactor. Add/adjust the `.feature` scenario and regenerate with
   `dart run build_runner build --delete-conflicting-outputs`.
3. `flutter analyze` (zero-warning bar) + `dart format lib test`.
4. `flutter test` (host suite green).
5. Device verification where the plan requires it:
   `flutter test integration_test/<x>_device_test.dart -d <android-id>` **and** `-d <ios-id>`.
   For OpenCV host exercises: `bash scripts/setup-cv-host-test.sh` then export the printed paths.
6. Only then mark the task done; paste the green output. **No "should work."**

The suggested overall sequence: **Wave A → Wave B → Wave C**, verifying green between waves so
`master` is always shippable.
