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
| **P03** | Persistence atomicity (merge/split txns) | 1 Safety | M | Med | P10 (soft, same-file) · P00 | both |
| **P04** | UI async-safety bugs | 1 Safety | S–M | Med | — | both |
| **P05** | Decompose the God repository | 2 SOLID | L | Med | (P10 first, soft) | both |
| **P06** | Extract view controllers from God widgets | 2 SOLID | L | Med | P00 | both |
| **P07** | Scan orchestration extraction | 2 SOLID | M | Med | — | both |
| **P08** | Native processor SOLID split + test seam | 2 SOLID | L | Med | P01 (soft, same-file) | Android+iOS |
| **P09** | Image-pipeline DRY & parity | 3 DRY | M–L | Med | (P08 soft) | both (parity) |
| **P10** | Repository DRY (helpers, temp-export, paths) | 3 DRY | S–M | Low | P00 | both |
| **P11** | Share-action model + flag gating | 3 DRY | M | Low | (P06 soft) | both |
| **P12** | Query & scaling (`_summaries`, N+1, sort) | 4 Perf | M | Low | P10 (soft, same-file) | host+both |
| **P13** | UI image memory & decoding | 4 Perf | M | Med | — | Android+iOS |
| **P14** | DI consistency, observability & 2°-feature cleanups | 3 Consistency | S–M | Low | P00 | both |
| **P15** | Hygiene: theme tokens, i18n date, lints, pins | 5 Hygiene | S–M | Low | — | host+both |

---

## 2. Dependency graph

```
Hard prerequisite (logical — P00 must land before its dependents):
P00 ──┬─▶ P02   (timeouts adopt withIsolateTimeout + AppLogger)
      ├─▶ P06   (runGuarded / AppLogger)
      ├─▶ P10   (TempFileWriter for _writeTempExport; AppLogger)
      └─▶ P14   (AppLogger sinks)

Same-file serialization lanes (all members edit ONE file — run one at a time in
the recommended order to avoid rebases; ordering is convenience, not correctness):
  native_page_processor.dart    :  P01 → P08 → P09
  drift_document_repository.dart :  P10 → P03 → P05   (and P12, any time after P10)

Soft cross-plan edge (reduces friction if ordered):
  P06 → P11   (controllers make the share-action wiring cleaner)

Fully independent (no inbound edges, any file): P04, P07, P13, P15
```

**P00 is the only hard logical prerequisite.** The two lanes above are *same-file* serializations:
their members edit a single file, so land them one at a time in the recommended order to avoid
painful rebases — but the order is a convenience, not a correctness gate. A safety-first team may
land P03 (corruption fix) or P12 (query fix) *before* P10 (a low-risk DRY cleanup) and simply
rebase P10's helpers on top; the P03/P12/P08 plan headers mark these edges "soft, same-file".

---

## 3. Execution tracks (parallel lanes, serial within a lane)

Two files concentrate most of the work, so think in **tracks that run in parallel**, each
**serialized internally**. Land + verify green at each step; a track never blocks another track,
and within a plan the tasks fan out to further subagents.

| Track | Order (serial) | Notes |
|---|---|---|
| **Foundation** | `P00` | Must land first; unblocks P02 / P06 / P10 / P14. |
| **Native pipeline** (`native_page_processor.dart`) | `P01 → P08 → P09` | Safety (OOM) first, then the SOLID split, then DRY/parity. |
| **Persistence** (`drift_document_repository.dart`) | `P10 → P03 → P05`, then `P12` | DRY helpers → atomicity → the big split; P12 (query) any time after P10. Safety-first? land P03 before P10 and rebase. |
| **Library UI** | `P06 → P11`; `P13` alongside | Controllers first (needs P00), then the share-action model; image-memory (P13) is independent. |
| **Independent** (start any time) | `P02`\*, `P04`, `P07`, `P14`\*, `P15` | \*P02 & P14 need P00 first. P04 / P07 / P15 have no inbound edges. |

**Suggested cadence:** land **P00** first, then run the tracks concurrently, prioritizing the
**safety** step at the head of each (P01, P03, P04) before the structural/DRY steps. Keep `master`
green after every step so it is always shippable.

> The tracks are guidance, not gates: a team with capacity can start any independent plan or any
> lane head immediately. The only firm rules are "P00 before its dependents" and "one editor at a
> time per same-file lane".

---

## 4. Why this order

1. **Safety before structure.** The OOM float-copies (P01), non-atomic merge/split (P03), missing
   timeouts (P02), and the async bugs (P04) are the only items that can crash, corrupt, or hang the
   app in the field. They ship first, as small targeted fixes, *before* the large decompositions.
2. **Foundations enable de-duplication.** `AppLogger`/`withIsolateTimeout`/`TempFileWriter` (P00)
   are what let P02/P06/P10/P14 collapse the 32-way toast duplication, the 8 unguarded isolates,
   and the 7 temp-file sites without inventing the same helper five times.
3. **Cleanups before the big split.** Extracting the repo's `_requirePage`/`_cloneSourcePage`/
   `_writeTempExport` helpers (P10) shrinks the surface P05 then carves into collaborators.
4. **Same-file plans are serialized.** P01→P08→P09 all edit `native_page_processor.dart`; P10→P03→P05
   (and P12) all edit `drift_document_repository.dart`. Serializing each lane avoids painful rebases
   while keeping every *other* track parallel.

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

The suggested overall sequence: land **P00**, then run the tracks in §3 concurrently — the
**safety** step at the head of each first (P01, P03, P04) — verifying green after every step so
`master` is always shippable.
