# Verification Protocol (binding)

This protocol exists because a "done" was once claimed on a check that **silently
did nothing** (`timeout` was missing, the command produced no output, and absence
of output was mistaken for success — with a stale side-signal filling the gap).
It must never recur. Every step, feature, and acceptance criterion is gated by
the rules below. This protocol is part of the Definition of Done.

## The rules (every acceptance criterion)

1. **Criterion → command → marker.** Each acceptance checkbox maps to an exact
   command and an exact expected **success marker** in that command's output. A
   box is ticked only when the captured actual output contains the marker.
2. **Silence is FAILURE.** Missing marker, empty output, or an unverified command
   is a FAIL — never a pass. Absence of evidence is not evidence.
3. **Assert exit codes.** A non-zero exit (unless explicitly expected) is a FAIL,
   independent of output.
4. **Tool preconditions.** Verify every tool the check relies on exists
   (`command -v <tool>`) before using it. A missing tool is a FAIL, not a skip.
   (This is the exact bug that slipped through: `timeout` was absent.)
5. **Negative control.** Where state could be stale, first force the system into
   a known-**failing** state (force-stop the app, delete the build artifact,
   clear the cache) so a stale pass is impossible. Then prove the action under
   test moves it to the passing state.
6. **No cache masking.** Run build/test/analyze with caching disabled
   (`--skip-nx-cache`) so a cached result can neither mask a failure nor stand in
   for a real run.
7. **Reproduce independently.** Never tick a box from another agent's report.
   Re-run the check yourself and observe the output.
8. **Store evidence.** Logs and screenshots are written to
   `.superpowers/verify/` (git-ignored) and referenced from the spec checkbox.

## The mechanism (per step)

- **Every step ships a verify script:** `scripts/verify/<step>.sh`, sourcing
  `scripts/verify/lib.sh`. It encodes all of the step's acceptance criteria as
  asserts (rules 1–6), saves evidence, prints a PASS/FAIL line per criterion, and
  **exits non-zero if any criterion fails**. `lib.sh` treats a missing marker as
  FAIL by construction, so rule 2 cannot be forgotten.
- **The progression gate is the script's exit code.** A step is "done" only when
  `scripts/verify/<step>.sh` exits 0, **observed**, not narrated.
- **Independent adversarial verifier.** After the implementer and the task
  reviewer, a **separate** subagent runs `scripts/verify/<step>.sh` from a clean
  state, tries to **disprove** "done," and reports PASS/FAIL per criterion with
  evidence. The controller marks the step complete only when the independent
  verifier agrees. The controller does not self-certify device/runtime criteria.

## Authoring a step's verify script

For each acceptance criterion, add one assert that:
- names the criterion,
- runs the real command (cache disabled),
- checks exit code **and** the positive marker,
- applies a negative control if stale state is possible,
- writes its log/screenshot to `$EVIDENCE_DIR`.

If a criterion genuinely cannot be machine-checked, that is itself a finding —
make the script print it as a FAIL with the reason, never a silent skip.
