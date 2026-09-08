# Legal documents: Terms, Privacy, FAQ — shared across app and web

**Date:** 2026-09-08
**Status:** design approved, spec under review

## Problem

The app has no Terms of Service, no in-app Privacy Policy, and no FAQ. The
website has a good `privacy.html`, no terms page at all, and five FAQ entries
buried in `support.html`. Neither surface carries a disclaimer of warranty or a
limitation of liability, and neither states that the user — not the developer —
is responsible for what they scan and for keeping their own backups.

Two documents also make claims that are now inaccurate: `privacy.html` predates
the iOS in-app-purchase tip jar and never mentions purchases, and
`index.html`'s "💸 Free" / "No data collected" badges are unqualified.

## Goals

1. Users can read Terms, Privacy, and FAQ **inside the app, offline, in their
   own language** (all 11 supported locales).
2. The same three documents are published on the website, also in 11 locales.
3. **One source of truth.** App text and web text are generated from the same
   files and cannot drift.
4. The documents disclaim warranty and liability as far as is honest and
   enforceable, and place responsibility for scanned content on the user.

## Non-goals

- No consent gate, first-run acceptance sheet, or re-consent flow. Assent is
  browsewrap: the Terms open with "By using ScannerCam Light you agree to these
  terms." (decided; see Accepted risks).
- No governing-law or venue clause (decided).
- No named publisher. Documents refer to "the developer of ScannerCam Light"
  and give the support email as the contact.
- No change to how feedback, donations, or the tip jar behave. This work
  describes them accurately; it does not alter them.

## Decisions

| Question | Decision |
|---|---|
| Where does content live | New `libs/legal-content/` package, source of truth for both surfaces |
| App localisation | All 11 locales, bundled, offline |
| Web localisation | All 11 locales, 33 generated pages |
| Consent | Passive notice only, no gate |
| Publisher | Unnamed individual developer, support email as contact |
| Governing law | Omitted, with a mandatory-local-rights carve-out |

## Architecture

### `libs/legal-content/` — the package

`pnpm-workspace.yaml` already globs `libs/*`, so this is a workspace package
with no changes to workspace config.

```
libs/legal-content/
  package.json            # @camscanner/legal-content, type: module
  README.md
  content/
    meta.json             # per-document version + effectiveDate (locale-independent)
    terms.en.json    …    terms.zh.json      (11)
    privacy.en.json  …    privacy.zh.json    (11)
    faq.en.json      …    faq.zh.json        (11)
  src/
    schema.mjs            # load + validate content, shared by generator and tests
    inline.mjs            # the restricted inline markup parser
    render-dart.mjs
    render-html.mjs
    generate.mjs          # entry point: writes both outputs
  test/
    schema.test.mjs       # node:test
    inline.test.mjs
```

Locales: `en, ar, de, es, fr, lb, pt, pt_BR, ru, tr, zh` — exactly the set in
`apps/mobile/lib/l10n/`. A test asserts the two lists stay equal, so adding an
app locale fails the legal build until its documents exist.

### Content schema

`content/meta.json` holds version and effective date **once per document**, so
translations cannot drift on dates:

```json
{ "terms":   { "version": "1.0.0", "effectiveDate": "2026-09-08" },
  "privacy": { "version": "1.1.0", "effectiveDate": "2026-09-08" },
  "faq":     { "version": "1.0.0", "effectiveDate": "2026-09-08" } }
```

Each `content/{doc}.{locale}.json`:

```json
{
  "doc": "terms",
  "locale": "pt_BR",
  "title": "Termos de Serviço",
  "effectiveDateLabel": "Em vigor desde",
  "translationNotice": "Esta tradução é fornecida por conveniência. Em caso de conflito, prevalece a versão em inglês.",
  "intro": "…",
  "sections": [
    { "id": "acceptance", "heading": "…",
      "body": [ { "type": "p",  "text": "…" },
                { "type": "ul", "items": ["…", "…"] } ] }
  ]
}
```

Only two block types, `p` and `ul`. Inline markup is a deliberately tiny
subset — `**bold**` and `[label](url)` — implemented once in `inline.mjs` and
mirrored by a Dart inliner, both covered by tests using the same fixtures.

Note what is *not* in ARB: titles, the effective-date label, and the
translation notice all come from this package, so the app and the web page show
identical wording. `app_*.arb` gains exactly **one** key,
`settingsSectionLegal` — keeping `test/l10n/arb_parity_test.dart` focused on UI
chrome and legal prose out of it entirely.

### Generator and outputs

`node libs/legal-content/src/generate.mjs` (from the repo root) writes, and **commits**:

- `apps/mobile/lib/features/legal/generated/legal_content.g.dart` — `const` maps
  keyed by document and locale. Synchronous, no assets, no `rootBundle`, so
  widget tests need no asset mocking.
- `apps/web/terms.html`, `apps/web/privacy.html`, `apps/web/faq.html` — English,
  at top level. **`privacy.html` keeps its exact existing URL**, which is
  registered in App Store Connect and Play Console.
- `apps/web/legal/{doc}.{locale}.html` — the other 10 locales, using the
  existing `styles.css` and site chrome, with `hreflang` alternates,
  `x-default` pointing at the English top-level page, and a no-JS `<nav>`
  language switcher.

Outputs are committed because `pages.yml` uploads `apps/web/` verbatim with no
build step; generating at deploy time would mean introducing one.

`scripts/check-legal-content.sh` re-runs the generator and fails if any output
differs from what is committed — same role as `scripts/check-theme-tokens.sh`.
A new `.github/workflows/legal-content.yml` runs it on any change to
`libs/legal-content/**`, `apps/web/**`, or `apps/mobile/lib/features/legal/**`,
and `pages.yml` gains `libs/legal-content/**` to its `paths` filter.

### App integration

New `apps/mobile/lib/features/legal/`:

- `legal_doc.dart` — `enum LegalDoc { terms, privacy, faq }`.
- `legal_content.dart` — hand-written API over the generated maps:
  `legalDocument(LegalDoc, Locale)`, falling back to English for a missing
  locale. The generated file is never imported outside this one.
- `legal_inline.dart` — the Dart half of the inline parser, producing
  `TextSpan`s (`**bold**`, tappable `[label](url)` via `url_launcher`, matching
  `donation_screen.dart`'s existing `launchUrl` seam so tests can inject).
- `legal_document_screen.dart` — one screen renders any document.
  `LegalDocumentScreen.route(LegalDoc)` mirrors the existing
  `DonationScreen.route()` / `FeedbackScreen.route()` helpers. Uses
  `AppBackHeader` and `context.appColors`, so theming is inherited. Terms and
  Privacy render as headings and paragraphs; FAQ renders the identical model as
  `ExpansionTile`s (heading = question, body = answer). Non-English documents
  show `translationNotice` above the body; all show the effective date.

`settings_screen.dart` gains an `AppSectionLabel(context.l10n.settingsSectionLegal)`
section after "Feedback & support" and before the About footer, with three
`_NavRow`s keyed `settings-terms`, `settings-privacy`, `settings-faq`. Row
labels come from the content package's `title`, so they are already localised.
`_NavRow` stays private — the new rows live in the same file.

**Deliberately not `FEATURE_*`-gated.** Every other user-facing action is
build-time strippable, but Apple and Google require the privacy policy to be
reachable; a flag that hides it is a store-rejection footgun. The exception is
documented in `feature_flags.dart`.

### Web integration

Beyond the generated pages:

- `support.html`'s inline FAQ block is replaced by a link to `faq.html`,
  removing the duplicate.
- Every page's footer gains **Terms · Privacy · FAQ**.
- `index.html`'s privacy claims are scoped to be accurate: the no-`INTERNET`
  claim is labelled Android-specific, and "Free" becomes "Free, with an
  optional tip".

## Document content

### Terms of Service

Acceptance by use · limited personal licence · **"AS IS", no warranty**
(merchantability, fitness, non-infringement) · **liability limited to zero, or
to the amount actually paid** · **the user is solely responsible for what they
scan**, for having the right to scan it, and for compliance with their local
law · **data-loss disclaimer** — no cloud, no backup; uninstalling or losing
the device destroys everything; keep your own copies · OCR and image
enhancement are not guaranteed accurate and must not be relied on for legal,
medical, or financial purposes · third-party services disclaimed by name
(Apple, Google, Ko-fi, Bitcoin, GitHub) · **tips and donations are voluntary,
non-refundable, and buy no product, feature, warranty, or support obligation** ·
indemnity · termination · severability · changes · mandatory-local-rights
carve-out · contact.

### Privacy Policy

The existing `privacy.html` text, ported into the structured model, plus what
it is missing: purchases (Apple processes payment; the developer receives no
payment or card data), the Android no-`INTERNET`-permission fact **scoped to
Android**, no analytics/ads/tracking/data sale, consent as the lawful basis for
the feedback path, retention (until you delete or uninstall), how to delete,
children, and a GDPR/CCPA statement that stays truthful for a no-collection
app.

### FAQ

Grows from 5 entries to ~14. New entries cover the tip jar, exactly what
feedback publishes publicly to GitHub, backups and data loss, OCR accuracy,
offline behaviour, and free-with-no-ads. Answers must not contradict the other
two documents; the parity test does not catch that, so it is a review item.

## Testing

Per `CLAUDE.md`, nothing is done without TDD **and** BDD, green on Android
**and** iOS.

**Package (node:test):** schema validation for all 33 files; section-`id`
parity against English; every non-English document carries `translationNotice`;
no empty headings or bodies; the package locale list equals
`apps/mobile/lib/l10n/`'s; inline-parser fixtures.

**App host tests:** `legal_content_test.dart` (lookup, English fallback);
`legal_inline_test.dart` (shares the package's fixtures); settings widget test
asserting the three rows appear and each pushes the right document; one screen
test per document type, including FAQ expansion and the non-English notice.

**BDD:** `test/bdd/legal_documents.feature` — open each document from settings,
read it in a non-English locale and see the notice, expand a FAQ entry.

**Web:** `scripts/check-legal-content.sh` drift check, plus a link check that
every generated page's footer and switcher targets resolve to a file that
exists.

**Device:** `integration_test/legal_documents_device_test.dart`, opening all
three documents, run on a real Android device and a real iOS device.

## Accepted risks

1. **Machine-translated legal text.** All 10 non-English versions are produced
   by me, not a lawyer or a professional translator. Mitigated by the
   "English version prevails" notice at the top of every translated document
   and by correct `hreflang`/`lang` so the English original is always
   reachable — but they remain unreviewed translations of a binding document.
2. **Browsewrap assent.** With no acceptance gate, the Terms are weaker than
   clickwrap if ever tested. Deliberate: the app has no account, collects no
   data, and the realistic liability surface is small.
3. **No governing law.** A dispute defaults to wherever a user sues. Deliberate.
4. **These are not lawyer-reviewed documents.** They are a good-faith,
   industry-standard disclaimer set. They materially improve on having nothing;
   they are not a substitute for counsel if real money is ever at stake.

## Pre-existing gaps found, not fixed here

- The Android release manifest has no `INTERNET` permission, so the feedback
  POST cannot succeed on an Android release build even when
  `FEEDBACK_WORKER_URL` and `TURNSTILE_SITE_KEY` are set. Feedback is currently
  hidden unless configured, so this is latent rather than user-visible. Out of
  scope; flagged for a separate task.

## Implementation shape

Per `CLAUDE.md`'s parallel-subagent rule, the work decomposes into independent
tasks with one true dependency: the English content and the schema must exist
before the generator, the translations, or either renderer. After that, the
Dart renderer, the HTML renderer, the 10 translations, the app screens, the
settings rows, the web chrome edits, and the guard script are all parallel. The
implementation plan follows in a separate document.
