# @camscanner/legal-content

Single source of truth for CamScanner-light's three legal documents — Terms of
Service, Privacy Policy, and FAQ — in all 11 supported locales. This package
does not ship at runtime; it is a build-time generator whose committed output
is what the app and the website actually use.

## The only hand-edited directory is `content/`

`content/` holds one hand-written JSON file per `(document, locale)` pair —
`terms.en.json`, `privacy.de.json`, and so on — plus `meta.json` (version and
effective date per document, shared across all locales). Everything else in
this package's output is generated. Never hand-edit a generated file; edit the
matching `content/*.json` and regenerate.

## What gets generated, and why it's committed

Two independent generators read `content/` and write into the rest of the
monorepo:

1. **`node src/generate.mjs`** writes:
   - `apps/mobile/lib/features/legal/generated/legal_content.g.dart` — a const
     Dart map the in-app Settings screen renders directly, keyed by document
     then locale.
   - `apps/web/{terms,privacy,faq}.html` (English, top-level) and
     `apps/web/legal/{doc}.{web-tag}.html` for the other 10 locales (33 pages
     total) — the standalone web pages.

2. **`node src/inline-parity-fixture.mjs`** writes:
   - `apps/mobile/test/features/legal/inline_parity_fixture.json` — the
     tokenisation of every string in the corpus (1400+ strings), so a Dart
     test can assert `parseLegalInline()` agrees with the JS `parseInline()`
     on the same input, across the entire real corpus rather than a handful
     of hand-picked cases.

All of it is committed, not built on demand, because
`.github/workflows/pages.yml` uploads `apps/web/` to GitHub Pages **verbatim,
with no build step**. If the HTML weren't committed, the site would never see
a content change.

## Regenerating

Run both, from the repo root, after any edit under `content/`:

```bash
node libs/legal-content/src/generate.mjs
node libs/legal-content/src/inline-parity-fixture.mjs
```

Do not run these through `pnpm --filter @camscanner/legal-content generate` —
pnpm's implicit dependency check spawns an inner `pnpm install` that has
corrupted `pnpm-workspace.yaml` in this repo's dev environment more than once.
Plain `node` is what CI uses too (see `scripts/check-legal-content.sh` and
`.github/workflows/legal-content.yml`).

`bash scripts/check-legal-content.sh` runs the test suite, regenerates both
outputs, and fails if anything committed doesn't match what came out —
whether that's a modified file or a new one that was generated but never
committed. Run it before committing a `content/` change; CI runs it on every
push and pull request that touches this package, `apps/web/`, or the
generated Dart.

## Adding a locale

1. Add the locale tag to `LOCALES` in `src/constants.mjs`. It must stay
   identical to `kSupportedAppLocales` in
   `apps/mobile/lib/l10n/locale_resolution.dart` — a node test enforces this.
2. Add the three content files: `terms.<locale>.json`, `privacy.<locale>.json`,
   `faq.<locale>.json`, following the shape of the English files (see
   `src/schema.mjs` for the required fields, including the non-English
   `translationNotice`).
3. Regenerate (see above) and run `cd libs/legal-content && node --test` —
   the parity tests check block-structure and section-id parity against
   English, so a malformed or partially-translated file fails loudly rather
   than shipping silently.

## Do not move `apps/web/privacy.html`

Its URL is registered with Apple (App Store Connect) and Google (Play
Console) as this app's privacy policy link. Moving, renaming, or removing
that file breaks both store listings. If the site's URL structure ever needs
to change, update the store listings first and keep the old path serving a
redirect.
