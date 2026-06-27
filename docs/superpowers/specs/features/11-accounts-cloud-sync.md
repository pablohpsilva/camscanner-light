# Feature 11 — Accounts & Cloud Sync

**Date:** 2026-06-27
**Status:** Deferred (upcoming feature)
**Sub-project:** 5 — Accounts & cloud sync

## Decision

**Deferred for now.** Cloud sync inherently moves documents off-device, which
conflicts with the project's privacy posture (documents never leave the device).
Rather than compromise that now, accounts and sync are postponed.

## Near-term behavior (what ships instead)

- **Local-only storage:** all files live on the user's device.
- **Clear communication:** the app presents sync/accounts as an **upcoming
  feature**, and makes clear that data is **device-local** — switching phones,
  reinstalling, or using another device will **not** carry the same files.
- This sets correct user expectations and avoids surprise data "loss."

## Future direction (when revisited)

1. **Manual export / "sync via file sharing":** a clean way to export and move
   documents as files (device-to-device, user-controlled). Lightweight first
   step toward portability without a backend.
2. **End-to-end encrypted sync (our backend):** account + cloud where documents
   are encrypted on-device; server stores only ciphertext. Needs a key-recovery
   story.
3. **Bring-your-own-cloud:** sync via the user's iCloud Drive / Google Drive /
   Dropbox; no servers of ours.

Any future implementation sits behind a `SyncProvider` interface (DIP) so it
does not disturb the local-only storage model.

## Out of scope (now)

- Authentication, backend, multi-device sync, cloud storage.

## Acceptance criteria (near-term)

1. The app clearly indicates sync/accounts is an upcoming feature.
2. Users understand data is stored only on their device.
3. No backend or account dependency is introduced.

---

> **Definition of Done gate:** Per the Definition of Done in `00-overview-roadmap.md`, this feature is **not done** until every acceptance criterion above is mapped to a passing TDD test and (for user-facing behavior) a BDD scenario, the full suite is run and observed green, quality gates pass, and the work is reviewed and double-checked. "Looks right" / "should pass" is not done.
