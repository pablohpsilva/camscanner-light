# Android release

> Load this when producing an Android release artifact.

`bash scripts/build-release.sh` — split-per-abi APKs + App Bundle, obfuscated,
symbols in `apps/mobile/build/symbols/`.

Before trusting the artifact, run `bash scripts/verify-artifact.sh
apps/mobile/build/app/outputs/flutter-apk/app-release.apk` to confirm it is a
Release (AOT) build, not a Debug stub.

R8/minify is viable with keep rules for mlkit/gms/flutter/rainyl **and** the OS
document scanner (`biz.cunning.**`). Missing keep rules break Release-only, and
scan device BDD uses fake scanners on Debug builds — so the breakage is
invisible to tests. Smoke-test the REAL scanner on a Release build before
shipping (see `docs/claude/review-checklist.md`).
