# Legal Documents (Terms / Privacy / FAQ) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship Terms of Service, Privacy Policy, and FAQ readable offline in-app in all 11 locales and published as 33 pages on the website, both generated from one shared source package so they can never drift.

**Architecture:** A new pnpm workspace package `libs/legal-content/` holds hand-edited JSON content (3 documents × 11 locales) plus a Node generator. The generator emits two **committed** artifacts: a `const` Dart file consumed by a new `apps/mobile/lib/features/legal/` feature, and static HTML into `apps/web/`. A guard script re-runs the generator and fails on any diff, so the committed outputs cannot drift from the source.

**Tech Stack:** Node 20 ESM + `node:test` (generator and its tests), Flutter/Dart (app), plain static HTML/CSS (web), pnpm workspaces, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-legal-documents-design.md`

## Global Constraints

- **Do not break what works.** The existing host suite must stay green after every task. `apps/web/privacy.html` **must keep its exact current URL** — it is registered in App Store Connect and Play Console. `pages.yml`'s deploy mechanism (upload `apps/web/` verbatim, no build step) must not change.
- **Run all Flutter commands from `apps/mobile/`**, never the repo root.
- **Locales (11, exact):** `en, pt, pt_BR, es, fr, de, lb, tr, ru, zh, ar` — the order and spelling of `kSupportedAppLocales` in `apps/mobile/lib/l10n/locale_resolution.dart`. `en` is the template and fallback.
- **Web locale tags use hyphens** (`pt-BR`), app/content tags use underscores (`pt_BR`). The generator converts.
- **Documents (3, exact):** `terms`, `privacy`, `faq`.
- **`app_*.arb` gains exactly one key: `settingsSectionLegal`.** All other legal wording — titles, effective-date label, translation notice — lives in the content package so app and web show identical text. Adding more ARB keys is a plan violation.
- **Publisher is unnamed:** documents say "the developer of ScannerCam Light". Contact is `scannercamlight.line149@passmail.net`. **No governing-law or venue clause.** Every document ends with a mandatory-local-rights carve-out.
- **Every non-English document carries `translationNotice`**, rendered above the body.
- **App name in copy:** `ScannerCam Light`.
- **Effective date for v1:** `2026-09-08`.
- **No `FEATURE_*` flag gates any legal screen** — deliberate exception to the repo's gate-everything convention, because Apple and Google require the privacy policy to be reachable.
- **TDD is mandatory** (`CLAUDE.md`): write the failing test, watch it fail, then implement. **BDD is mandatory** for user-facing behaviour. Device verification on a real Android device **and** a real iOS device is required before the work is called done.
- **Commit scope:** `git add` only the named paths. Never `git add -A` — this repo has a history of a long-lived uncommitted WIP pile.
- Branch: `feat/legal-documents` (already created; the spec is committed on it).

---

## File Structure

**New package — `libs/legal-content/`**
| File | Responsibility |
|---|---|
| `package.json` | Workspace package `@camscanner/legal-content`, ESM, `generate` + `test` scripts |
| `content/meta.json` | Per-document `version` + `effectiveDate`, locale-independent |
| `content/{doc}.{locale}.json` | 33 hand-edited content files — the only source of truth |
| `src/constants.mjs` | `DOCS`, `LOCALES`, `webTag()`, paths |
| `src/schema.mjs` | Load + validate a content file; throws with a precise message |
| `src/inline.mjs` | Restricted inline markup parser (`**bold**`, `[label](url)`) |
| `src/render-dart.mjs` | Content → `legal_content.g.dart` source string |
| `src/render-html.mjs` | Content → one HTML page string |
| `src/generate.mjs` | Entry point; writes all outputs |
| `test/*.test.mjs` | `node:test` suites |

**New app feature — `apps/mobile/lib/features/legal/`**
| File | Responsibility |
|---|---|
| `legal_doc.dart` | `enum LegalDoc { terms, privacy, faq }` |
| `legal_models.dart` | `LegalDocument`, `LegalSection`, `LegalBlock` (sealed) |
| `legal_inline.dart` | Dart half of the inline parser → `List<LegalInlineSpan>` |
| `legal_content.dart` | `legalDocument(LegalDoc, Locale)` with English fallback |
| `generated/legal_content.g.dart` | **Generated, committed.** Never imported outside `legal_content.dart` |
| `legal_document_screen.dart` | One screen renders any document; `route()` helper |

**Modified**
| File | Change |
|---|---|
| `apps/mobile/lib/features/settings/settings_screen.dart` | New "Legal" section, three `_NavRow`s |
| `apps/mobile/lib/l10n/app_*.arb` (11) | One key: `settingsSectionLegal` |
| `apps/mobile/lib/features/library/feature_flags.dart` | Doc comment noting the deliberate no-flag exception |
| `apps/web/index.html`, `support.html` | Footer links; scoped privacy claims; FAQ de-duplicated |
| `.github/workflows/pages.yml` | Add `libs/legal-content/**` to `paths` |

**Generated web output (committed):** `apps/web/{terms,privacy,faq}.html` (English, top level) and `apps/web/legal/{doc}.{web-tag}.html` (other 10 locales).

---

### Task 1: Package scaffold, constants, and schema validator

**Files:**
- Create: `libs/legal-content/package.json`
- Create: `libs/legal-content/src/constants.mjs`
- Create: `libs/legal-content/src/schema.mjs`
- Create: `libs/legal-content/content/meta.json`
- Test: `libs/legal-content/test/schema.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: `DOCS: string[]`, `LOCALES: string[]`, `webTag(locale: string): string`, `contentDir: string`, `repoRoot: string` from `constants.mjs`; `validateDocument(json, {doc, locale}): void` (throws `Error` on invalid), `loadDocument(doc, locale): object`, `loadMeta(): object` from `schema.mjs`.

- [ ] **Step 1: Write the failing test**

Create `libs/legal-content/test/schema.test.mjs`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { DOCS, LOCALES, webTag } from '../src/constants.mjs'
import { validateDocument } from '../src/schema.mjs'

const valid = () => ({
  doc: 'terms',
  locale: 'en',
  title: 'Terms of Service',
  effectiveDateLabel: 'Effective date',
  translationNotice: '',
  intro: 'Intro text.',
  sections: [
    { id: 'acceptance', heading: 'Acceptance', body: [{ type: 'p', text: 'Body.' }] },
  ],
})

test('DOCS and LOCALES are the agreed sets', () => {
  assert.deepEqual(DOCS, ['terms', 'privacy', 'faq'])
  assert.deepEqual(LOCALES, ['en', 'pt', 'pt_BR', 'es', 'fr', 'de', 'lb', 'tr', 'ru', 'zh', 'ar'])
})

test('webTag hyphenates region tags', () => {
  assert.equal(webTag('pt_BR'), 'pt-BR')
  assert.equal(webTag('en'), 'en')
})

test('a well-formed document validates', () => {
  assert.doesNotThrow(() => validateDocument(valid(), { doc: 'terms', locale: 'en' }))
})

test('rejects a document whose doc/locale disagree with the filename', () => {
  assert.throws(() => validateDocument(valid(), { doc: 'privacy', locale: 'en' }), /doc "terms".*expected "privacy"/)
})

test('rejects an empty heading', () => {
  const d = valid()
  d.sections[0].heading = '  '
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'en' }), /heading/)
})

test('rejects an empty body', () => {
  const d = valid()
  d.sections[0].body = []
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'en' }), /body/)
})

test('rejects an unknown block type', () => {
  const d = valid()
  d.sections[0].body = [{ type: 'table', text: 'x' }]
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'en' }), /block type "table"/)
})

test('rejects a ul block with no items', () => {
  const d = valid()
  d.sections[0].body = [{ type: 'ul', items: [] }]
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'en' }), /items/)
})

test('rejects duplicate section ids', () => {
  const d = valid()
  d.sections.push({ ...d.sections[0] })
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'en' }), /duplicate section id "acceptance"/)
})

test('requires a translation notice on non-English documents', () => {
  const d = { ...valid(), locale: 'de' }
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'de' }), /translationNotice/)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test`
Expected: FAIL — `Cannot find module '../src/constants.mjs'`.

- [ ] **Step 3: Write the implementation**

`libs/legal-content/package.json`:

```json
{
  "name": "@camscanner/legal-content",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "scripts": {
    "generate": "node src/generate.mjs",
    "test": "node --test"
  }
}
```

`libs/legal-content/src/constants.mjs`:

```js
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

/** The three documents. Order is the order they appear in Settings. */
export const DOCS = ['terms', 'privacy', 'faq']

/** Must equal kSupportedAppLocales in apps/mobile/lib/l10n/locale_resolution.dart. */
export const LOCALES = ['en', 'pt', 'pt_BR', 'es', 'fr', 'de', 'lb', 'tr', 'ru', 'zh', 'ar']

export const packageRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
export const repoRoot = resolve(packageRoot, '..', '..')
export const contentDir = resolve(packageRoot, 'content')

/** App/content tags use `_`; the web uses BCP-47 `-`. */
export const webTag = (locale) => locale.replace('_', '-')
```

`libs/legal-content/content/meta.json`:

```json
{
  "terms":   { "version": "1.0.0", "effectiveDate": "2026-09-08" },
  "privacy": { "version": "1.1.0", "effectiveDate": "2026-09-08" },
  "faq":     { "version": "1.0.0", "effectiveDate": "2026-09-08" }
}
```

`libs/legal-content/src/schema.mjs`:

```js
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { contentDir } from './constants.mjs'

const isNonEmpty = (v) => typeof v === 'string' && v.trim().length > 0

/** Throws with a precise, file-identifying message if `json` is not a valid document. */
export function validateDocument (json, { doc, locale }) {
  const where = `${doc}.${locale}.json`
  if (json.doc !== doc) throw new Error(`${where}: doc "${json.doc}" — expected "${doc}"`)
  if (json.locale !== locale) throw new Error(`${where}: locale "${json.locale}" — expected "${locale}"`)
  for (const field of ['title', 'effectiveDateLabel', 'intro']) {
    if (!isNonEmpty(json[field])) throw new Error(`${where}: ${field} must be a non-empty string`)
  }
  if (locale !== 'en' && !isNonEmpty(json.translationNotice)) {
    throw new Error(`${where}: translationNotice is required on non-English documents`)
  }
  if (!Array.isArray(json.sections) || json.sections.length === 0) {
    throw new Error(`${where}: sections must be a non-empty array`)
  }
  const seen = new Set()
  for (const s of json.sections) {
    if (!isNonEmpty(s.id)) throw new Error(`${where}: every section needs a non-empty id`)
    if (seen.has(s.id)) throw new Error(`${where}: duplicate section id "${s.id}"`)
    seen.add(s.id)
    if (!isNonEmpty(s.heading)) throw new Error(`${where}: section "${s.id}" has an empty heading`)
    if (!Array.isArray(s.body) || s.body.length === 0) {
      throw new Error(`${where}: section "${s.id}" has an empty body`)
    }
    for (const b of s.body) {
      if (b.type === 'p') {
        if (!isNonEmpty(b.text)) throw new Error(`${where}: section "${s.id}" has an empty p block`)
      } else if (b.type === 'ul') {
        if (!Array.isArray(b.items) || b.items.length === 0 || !b.items.every(isNonEmpty)) {
          throw new Error(`${where}: section "${s.id}" has a ul block with empty items`)
        }
      } else {
        throw new Error(`${where}: section "${s.id}" has unknown block type "${b.type}"`)
      }
    }
  }
}

export function loadMeta () {
  return JSON.parse(readFileSync(resolve(contentDir, 'meta.json'), 'utf8'))
}

/** Reads, parses, and validates one content file. */
export function loadDocument (doc, locale) {
  const json = JSON.parse(readFileSync(resolve(contentDir, `${doc}.${locale}.json`), 'utf8'))
  validateDocument(json, { doc, locale })
  return json
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd libs/legal-content && node --test`
Expected: PASS, 10 tests.

- [ ] **Step 5: Install the workspace package and confirm nothing else broke**

Run: `cd /Users/pablohpsilva/Documents/camscanner-light && pnpm install`
Expected: succeeds; `@camscanner/legal-content` is picked up by the existing `libs/*` glob in `pnpm-workspace.yaml` with **no edit to that file**.

- [ ] **Step 6: Commit**

```bash
git add libs/legal-content/package.json libs/legal-content/src/constants.mjs \
        libs/legal-content/src/schema.mjs libs/legal-content/content/meta.json \
        libs/legal-content/test/schema.test.mjs pnpm-lock.yaml
git commit -m "feat(legal): content package scaffold and schema validator"
```

---

### Task 2: Inline markup parser (JavaScript)

Independent of Task 1 — pure string handling. Can run in parallel with Tasks 3-5.

**Files:**
- Create: `libs/legal-content/src/inline.mjs`
- Test: `libs/legal-content/test/inline.test.mjs`

**Interfaces:**
- Consumes: nothing.
- Produces: `parseInline(text: string): Array<{type:'text'|'bold'|'link', text: string, url?: string}>`. This token shape is mirrored exactly by the Dart parser in Task 9 — the two are tested against the same fixtures, so **do not change the token names without changing both.**

- [ ] **Step 1: Write the failing test**

Create `libs/legal-content/test/inline.test.mjs`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { parseInline } from '../src/inline.mjs'

test('plain text is one text token', () => {
  assert.deepEqual(parseInline('hello world'), [{ type: 'text', text: 'hello world' }])
})

test('bold in the middle splits into three tokens', () => {
  assert.deepEqual(parseInline('a **b** c'), [
    { type: 'text', text: 'a ' },
    { type: 'bold', text: 'b' },
    { type: 'text', text: ' c' },
  ])
})

test('a link keeps its label and url', () => {
  assert.deepEqual(parseInline('see [the policy](privacy.html) now'), [
    { type: 'text', text: 'see ' },
    { type: 'link', text: 'the policy', url: 'privacy.html' },
    { type: 'text', text: ' now' },
  ])
})

test('bold and link coexist', () => {
  assert.deepEqual(parseInline('**Note:** mail [us](mailto:a@b.c)'), [
    { type: 'bold', text: 'Note:' },
    { type: 'text', text: ' mail ' },
    { type: 'link', text: 'us', url: 'mailto:a@b.c' },
  ])
})

test('an unmatched asterisk pair stays literal', () => {
  assert.deepEqual(parseInline('2 ** 3'), [{ type: 'text', text: '2 ** 3' }])
})

test('empty string yields no tokens', () => {
  assert.deepEqual(parseInline(''), [])
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test test/inline.test.mjs`
Expected: FAIL — `Cannot find module '../src/inline.mjs'`.

- [ ] **Step 3: Write the implementation**

`libs/legal-content/src/inline.mjs`:

```js
// The ONLY inline markup allowed in legal content: **bold** and [label](url).
// Deliberately tiny — the Dart renderer must reimplement it exactly
// (apps/mobile/lib/features/legal/legal_inline.dart), so every addition here
// is a change in two languages plus two test suites.
const PATTERN = /\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]+)\)/g

/** @returns {Array<{type:'text'|'bold'|'link', text: string, url?: string}>} */
export function parseInline (text) {
  const tokens = []
  let last = 0
  for (const m of text.matchAll(PATTERN)) {
    if (m.index > last) tokens.push({ type: 'text', text: text.slice(last, m.index) })
    if (m[1] !== undefined) tokens.push({ type: 'bold', text: m[1] })
    else tokens.push({ type: 'link', text: m[2], url: m[3] })
    last = m.index + m[0].length
  }
  if (last < text.length) tokens.push({ type: 'text', text: text.slice(last) })
  return tokens
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd libs/legal-content && node --test test/inline.test.mjs`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add libs/legal-content/src/inline.mjs libs/legal-content/test/inline.test.mjs
git commit -m "feat(legal): restricted inline markup parser"
```

---

### Task 3: English Terms of Service content

Depends on Task 1 (schema). Parallel with Tasks 4 and 5.

**Files:**
- Create: `libs/legal-content/content/terms.en.json`
- Test: `libs/legal-content/test/terms_clauses.test.mjs`

**Interfaces:**
- Consumes: `loadDocument` from `src/schema.mjs`.
- Produces: `terms.en.json` with **exactly these section ids, in this order** — later tasks (translations, parity tests) depend on this list:
  `acceptance`, `licence`, `your-content`, `no-warranty`, `limitation-of-liability`, `data-loss`, `accuracy`, `third-parties`, `donations`, `acceptable-use`, `indemnity`, `termination`, `changes`, `your-rights`, `contact`.

- [ ] **Step 1: Write the failing test**

Create `libs/legal-content/test/terms_clauses.test.mjs`. This is the acceptance test for the prose: it asserts the load-bearing clauses are actually present, not just that the file parses.

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('terms', 'en')
const allText = (d) => JSON.stringify(d).toLowerCase()

const EXPECTED_IDS = [
  'acceptance', 'licence', 'your-content', 'no-warranty', 'limitation-of-liability',
  'data-loss', 'accuracy', 'third-parties', 'donations', 'acceptable-use',
  'indemnity', 'termination', 'changes', 'your-rights', 'contact',
]

test('has exactly the agreed sections, in order', () => {
  assert.deepEqual(doc().sections.map((s) => s.id), EXPECTED_IDS)
})

test('states that use constitutes acceptance', () => {
  const s = doc().sections.find((x) => x.id === 'acceptance')
  assert.match(JSON.stringify(s).toLowerCase(), /by using/)
})

test('disclaims warranty in the conventional terms', () => {
  const t = allText(doc())
  for (const phrase of ['as is', 'without warranty', 'merchantability', 'fitness for a particular purpose', 'non-infringement']) {
    assert.ok(t.includes(phrase), `missing warranty phrase: ${phrase}`)
  }
})

test('limits liability and names the cap', () => {
  const s = doc().sections.find((x) => x.id === 'limitation-of-liability')
  const t = JSON.stringify(s).toLowerCase()
  assert.match(t, /amount you (have )?actually paid/)
  assert.match(t, /indirect|consequential/)
})

test('places responsibility for scanned content on the user', () => {
  const s = doc().sections.find((x) => x.id === 'your-content')
  const t = JSON.stringify(s).toLowerCase()
  assert.match(t, /solely responsible/)
  assert.match(t, /right to (scan|copy)/)
})

test('warns about data loss and tells the user to keep backups', () => {
  const s = doc().sections.find((x) => x.id === 'data-loss')
  const t = JSON.stringify(s).toLowerCase()
  assert.match(t, /no backup|not backed up/)
  assert.match(t, /own (copies|backups)/)
})

test('says OCR output must not be relied on for legal, medical or financial purposes', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'accuracy')).toLowerCase()
  for (const w of ['legal', 'medical', 'financial']) assert.ok(t.includes(w), `missing: ${w}`)
})

test('says donations and tips are non-refundable and buy nothing', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'donations')).toLowerCase()
  assert.match(t, /non-refundable/)
  assert.match(t, /voluntary/)
})

test('preserves mandatory local consumer rights', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'your-rights')).toLowerCase()
  assert.match(t, /cannot be (excluded|limited)|mandatory/)
})

test('names no governing law or court', () => {
  const t = allText(doc())
  for (const w of ['governing law', 'jurisdiction of the courts', 'exclusive jurisdiction', 'venue']) {
    assert.ok(!t.includes(w), `must not contain a governing-law clause: ${w}`)
  }
})

test('names no individual person as publisher', () => {
  assert.ok(allText(doc()).includes('the developer of scannercam light'))
})

test('gives the support email', () => {
  assert.match(allText(doc()), /scannercamlight\.line149@passmail\.net/)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test test/terms_clauses.test.mjs`
Expected: FAIL — `ENOENT ... content/terms.en.json`.

- [ ] **Step 3: Write the content**

Create `libs/legal-content/content/terms.en.json` with `doc: "terms"`, `locale: "en"`, `title: "Terms of Service"`, `effectiveDateLabel: "Effective date"`, `translationNotice: ""`, an `intro` stating the app is a free, on-device document scanner and that these terms govern its use, and the 15 sections above. Write real prose — every clause listed in the spec's "Terms of Service" section must appear. Key wording the tests pin:

- `acceptance` — "By using ScannerCam Light you agree to these terms. If you do not agree, do not use the app."
- `your-content` — "**You are solely responsible** for the documents you scan, store, and share with ScannerCam Light, for having the right to scan or copy them, and for your use complying with the laws that apply to you."
- `no-warranty` — "ScannerCam Light is provided **\"as is\" and \"as available\", without warranty of any kind**, express or implied, including but not limited to the implied warranties of merchantability, fitness for a particular purpose, and non-infringement."
- `limitation-of-liability` — no liability for any indirect, incidental, special, consequential, or exemplary damages, nor for lost data or lost profits; total liability capped at "the amount you have actually paid for the app, which for ScannerCam Light is normally nothing".
- `data-loss` — documents live only on the device, are **not backed up** to any server, and are destroyed by uninstalling the app, clearing its data, or losing the device; "keep your own copies of anything you cannot afford to lose."
- `accuracy` — edge detection, perspective correction, image enhancement, and OCR are automated and imperfect; output "must not be relied on for legal, medical, financial, or other consequential purposes without checking it against the original."
- `third-parties` — Apple, Google, Ko-fi, the Bitcoin network, and GitHub are named as independent third parties governed by their own terms.
- `donations` — tips and donations are voluntary, **non-refundable**, and grant no product, feature, warranty, priority, or support obligation.
- `your-rights` — "Nothing in these terms limits any right you have under the consumer-protection law of your own country that cannot be excluded or limited by agreement."
- `contact` — links the support email with `[…](mailto:scannercamlight.line149@passmail.net)` and links the privacy policy with `[Privacy Policy](privacy.html)`.

Use `**bold**` for the load-bearing disclaimers and `ul` blocks for enumerations.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd libs/legal-content && node --test test/terms_clauses.test.mjs`
Expected: PASS, 12 tests.

- [ ] **Step 5: Commit**

```bash
git add libs/legal-content/content/terms.en.json libs/legal-content/test/terms_clauses.test.mjs
git commit -m "feat(legal): English Terms of Service content"
```

---

### Task 4: English Privacy Policy content

Depends on Task 1. Parallel with Tasks 3 and 5.

**Files:**
- Create: `libs/legal-content/content/privacy.en.json`
- Test: `libs/legal-content/test/privacy_clauses.test.mjs`

**Interfaces:**
- Consumes: `loadDocument` from `src/schema.mjs`.
- Produces: `privacy.en.json` with **exactly these section ids, in this order**:
  `summary`, `what-we-collect`, `where-data-lives`, `network`, `feedback`, `purchases`, `sharing`, `retention`, `your-rights`, `children`, `changes`, `contact`.

Source material: the current `apps/web/privacy.html` is accurate and well-written — port its wording rather than inventing new text, then add the missing sections (`purchases`, `retention`, `your-rights`).

**Exact values, required verbatim:** `"title": "Privacy Policy"` and `"effectiveDateLabel": "Effective date"`. Task 12 labels the Settings row from this `title` and asserts `find.text('Privacy Policy')`, so any other wording fails a later task.

- [ ] **Step 1: Write the failing test**

Create `libs/legal-content/test/privacy_clauses.test.mjs`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('privacy', 'en')
const allText = (d) => JSON.stringify(d).toLowerCase()
const section = (id) => JSON.stringify(doc().sections.find((s) => s.id === id)).toLowerCase()

const EXPECTED_IDS = [
  'summary', 'what-we-collect', 'where-data-lives', 'network', 'feedback',
  'purchases', 'sharing', 'retention', 'your-rights', 'children', 'changes', 'contact',
]

test('has exactly the agreed sections, in order', () => {
  assert.deepEqual(doc().sections.map((s) => s.id), EXPECTED_IDS)
})

test('says scans, OCR and storage stay on the device', () => {
  const t = section('where-data-lives')
  assert.match(t, /on your device/)
  assert.match(t, /ocr|text recognition/)
})

test('discloses that feedback creates a PUBLIC GitHub issue', () => {
  const t = section('feedback')
  assert.match(t, /public/)
  assert.match(t, /github/)
  assert.match(t, /email/)
})

test('states no scanned documents are ever sent', () => {
  assert.match(section('feedback'), /no scanned documents/)
})

test('covers in-app purchases and says Apple processes payment', () => {
  const t = section('purchases')
  assert.match(t, /apple/)
  assert.match(t, /tip/)
  assert.ok(/no payment|never receive|do not receive/.test(t), 'must say the developer receives no payment data')
})

test('scopes the no-INTERNET-permission claim to Android', () => {
  const t = section('network')
  assert.match(t, /android/)
  assert.match(t, /internet permission/)
})

test('says there is no tracking, no analytics, no ads and no sale of data', () => {
  const t = allText(doc())
  for (const w of ['no analytics', 'no ads', 'never sold', 'no tracking']) {
    assert.ok(t.includes(w), `missing claim: ${w}`)
  }
})

test('explains retention and how to delete everything', () => {
  const t = section('retention')
  assert.match(t, /uninstall/)
  assert.match(t, /delete/)
})

test('gives the support email', () => {
  assert.match(allText(doc()), /scannercamlight\.line149@passmail\.net/)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test test/privacy_clauses.test.mjs`
Expected: FAIL — `ENOENT ... content/privacy.en.json`.

- [ ] **Step 3: Write the content**

Port `apps/web/privacy.html`'s body into the schema, keeping its wording where it is already accurate, and add:

- `network` — must now say: "On **Android**, the released app does not request the `INTERNET` permission at all, so it cannot make network requests. On iOS there is no equivalent permission; the app still makes no background requests." (This is verified true: `android/app/src/main/AndroidManifest.xml` declares only `CAMERA`.)
- `purchases` — "On iOS the app offers an optional tip. Tips are processed entirely by **Apple**; the developer receives no payment-card details, no billing address, and no other payment data — only Apple's aggregate, anonymous sales reporting. On Android there is no in-app purchase; the donation links open your browser."
- `retention` — data is kept until you delete the document or uninstall; uninstalling removes the local database and every image file; no server-side copy exists to request deletion of.
- `your-rights` — because no personal data is collected or stored on any server, there is nothing to export, correct, or erase; the one exception is feedback you chose to submit, which is public on GitHub and can be removed on request via the support email. Mention GDPR and CCPA by name, and give consent as the lawful basis for the feedback path.
- `summary` — one paragraph replacing the current `lead`.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd libs/legal-content && node --test test/privacy_clauses.test.mjs`
Expected: PASS, 9 tests.

- [ ] **Step 5: Commit**

```bash
git add libs/legal-content/content/privacy.en.json libs/legal-content/test/privacy_clauses.test.mjs
git commit -m "feat(legal): English Privacy Policy content"
```

---

### Task 5: English FAQ content

Depends on Task 1. Parallel with Tasks 3 and 4.

**Files:**
- Create: `libs/legal-content/content/faq.en.json`
- Test: `libs/legal-content/test/faq_clauses.test.mjs`

**Interfaces:**
- Consumes: `loadDocument` from `src/schema.mjs`.
- Produces: `faq.en.json` where each **section is one question** (`heading` = question, `body` = answer). Exactly these ids, in this order:
  `offline`, `where-stored`, `is-it-free`, `tips`, `export-pdf`, `ocr-accuracy`, `search`, `backups`, `free-space`, `feedback-public`, `languages`, `ads-tracking`, `lost-phone`, `contact`.

  The five questions currently on `support.html` map to `offline`, `where-stored`, `export-pdf`, `is-it-free`, `free-space` — carry their existing answers over so the site's wording does not regress.

- [ ] **Step 1: Write the failing test**

Create `libs/legal-content/test/faq_clauses.test.mjs`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('faq', 'en')
const section = (id) => JSON.stringify(doc().sections.find((s) => s.id === id)).toLowerCase()

const EXPECTED_IDS = [
  'offline', 'where-stored', 'is-it-free', 'tips', 'export-pdf', 'ocr-accuracy',
  'search', 'backups', 'free-space', 'feedback-public', 'languages',
  'ads-tracking', 'lost-phone', 'contact',
]

test('has exactly the agreed questions, in order', () => {
  assert.deepEqual(doc().sections.map((s) => s.id), EXPECTED_IDS)
})

test('every question reads as a question', () => {
  for (const s of doc().sections) {
    assert.ok(s.heading.includes('?'), `not a question: "${s.heading}"`)
  }
})

test('the backups answer does not contradict the terms', () => {
  const t = section('backups')
  assert.match(t, /no (cloud|backup)|not backed up/)
  assert.match(t, /your own/)
})

test('the lost-phone answer is honest about total loss', () => {
  assert.match(section('lost-phone'), /gone|lost|cannot be recovered|no way to recover/)
})

test('the feedback answer repeats the public-GitHub warning', () => {
  const t = section('feedback-public')
  assert.match(t, /public/)
  assert.match(t, /github/)
})

test('the tips answer says tips are optional and unlock nothing', () => {
  const t = section('tips')
  assert.match(t, /optional|voluntary/)
  assert.ok(/unlock|no (extra )?features|nothing/.test(t))
})

test('the ocr answer does not overclaim accuracy', () => {
  assert.match(section('ocr-accuracy'), /not (always )?perfect|imperfect|check|may/)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test test/faq_clauses.test.mjs`
Expected: FAIL — `ENOENT ... content/faq.en.json`.

- [ ] **Step 3: Write the content**

Write the 14 Q&A pairs. `title: "Frequently Asked Questions"`. Answers must agree with the Terms and Privacy documents — particularly `backups`, `lost-phone`, `tips`, and `feedback-public`, which restate clauses those documents make binding. Link out with `[Privacy Policy](privacy.html)` / `[Terms of Service](terms.html)` where relevant.

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd libs/legal-content && node --test test/faq_clauses.test.mjs`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add libs/legal-content/content/faq.en.json libs/legal-content/test/faq_clauses.test.mjs
git commit -m "feat(legal): English FAQ content"
```

---

### Task 6: Dart renderer and the generated Dart artifact

Depends on Tasks 1-5 AND Task 8 (all 33 content files must exist). Runs BEFORE Task 7 — both tasks write `src/generate.mjs`.

**Files:**
- Create: `libs/legal-content/src/render-dart.mjs`
- Create: `libs/legal-content/src/generate.mjs`
- Create: `apps/mobile/lib/features/legal/legal_models.dart`
- Create: `apps/mobile/lib/features/legal/legal_doc.dart`
- Generate: `apps/mobile/lib/features/legal/generated/legal_content.g.dart`
- Test: `libs/legal-content/test/render_dart.test.mjs`

**Interfaces:**
- Consumes: `loadDocument`, `loadMeta`, `DOCS`, `LOCALES`.
- Produces: `renderDart(documents, meta): string` from `render-dart.mjs`; a `generate.mjs` entry point; and the Dart types the app depends on —
  - `enum LegalDoc { terms, privacy, faq }` with `String get key`
  - `class LegalDocument { final String title, effectiveDate, effectiveDateLabel, translationNotice, intro; final List<LegalSection> sections; }`
  - `class LegalSection { final String id, heading; final List<LegalBlock> body; }`
  - `sealed class LegalBlock`; `class LegalParagraph extends LegalBlock { final String text; }`; `class LegalBullets extends LegalBlock { final List<String> items; }`
  - generated `const Map<String, Map<String, LegalDocument>> kLegalContent` keyed `doc.key` → locale tag (`pt_BR` form).

- [ ] **Step 1: Write the failing test**

Create `libs/legal-content/test/render_dart.test.mjs`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { renderDart } from '../src/render-dart.mjs'

const meta = { terms: { version: '1.0.0', effectiveDate: '2026-09-08' } }
const docs = {
  terms: {
    en: {
      doc: 'terms', locale: 'en', title: 'Terms', effectiveDateLabel: 'Effective date',
      translationNotice: '', intro: 'Intro',
      sections: [{ id: 'a', heading: 'A', body: [{ type: 'p', text: "It's $safe" }, { type: 'ul', items: ['one'] }] }],
    },
  },
}

test('emits a generated-code banner and no analyzer noise', () => {
  const out = renderDart(docs, meta)
  assert.match(out, /GENERATED CODE - DO NOT MODIFY BY HAND/)
  assert.match(out, /ignore_for_file/)
})

test('emits a const map keyed by doc then locale', () => {
  const out = renderDart(docs, meta)
  assert.match(out, /const Map<String, Map<String, LegalDocument>> kLegalContent = \{/)
  assert.match(out, /'terms': \{/)
  assert.match(out, /'en': LegalDocument\(/)
})

test('carries the effective date from meta, not from the locale file', () => {
  assert.match(renderDart(docs, meta), /effectiveDate: '2026-09-08'/)
})

test('escapes single quotes and dollar signs so the Dart compiles', () => {
  const out = renderDart(docs, meta)
  assert.ok(out.includes("It\\'s \\$safe"), 'apostrophes and $ must be escaped')
})

test('renders both block types', () => {
  const out = renderDart(docs, meta)
  assert.match(out, /LegalParagraph\('/)
  assert.match(out, /LegalBullets\(\['one'\]\)/)
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test test/render_dart.test.mjs`
Expected: FAIL — `Cannot find module '../src/render-dart.mjs'`.

- [ ] **Step 3: Write the Dart model types by hand**

`apps/mobile/lib/features/legal/legal_doc.dart`:

```dart
/// The three legal documents, in the order they appear in Settings.
enum LegalDoc {
  terms('terms'),
  privacy('privacy'),
  faq('faq');

  const LegalDoc(this.key);

  /// Matches the `doc` field in libs/legal-content/content/*.json.
  final String key;
}
```

`apps/mobile/lib/features/legal/legal_models.dart`:

```dart
/// Immutable shape of a legal document. Mirrors the JSON schema in
/// libs/legal-content/src/schema.mjs — change one, change both.
class LegalDocument {
  final String title;
  final String effectiveDate;
  final String effectiveDateLabel;

  /// Empty for English; a "the English version prevails" notice otherwise.
  final String translationNotice;
  final String intro;
  final List<LegalSection> sections;

  const LegalDocument({
    required this.title,
    required this.effectiveDate,
    required this.effectiveDateLabel,
    required this.translationNotice,
    required this.intro,
    required this.sections,
  });
}

class LegalSection {
  final String id;
  final String heading;
  final List<LegalBlock> body;
  const LegalSection(this.id, this.heading, this.body);
}

sealed class LegalBlock {
  const LegalBlock();
}

class LegalParagraph extends LegalBlock {
  final String text;
  const LegalParagraph(this.text);
}

class LegalBullets extends LegalBlock {
  final List<String> items;
  const LegalBullets(this.items);
}
```

- [ ] **Step 4: Write the renderer and the generator entry point**

`libs/legal-content/src/render-dart.mjs`:

```js
import { DOCS, LOCALES } from './constants.mjs'

// Dart single-quoted string literal: backslash, quote, and $ need escaping;
// newlines must not break the literal.
const s = (v) => "'" + String(v)
  .replace(/\\/g, '\\\\')
  .replace(/'/g, "\\'")
  .replace(/\$/g, '\\$')
  .replace(/\n/g, '\\n') + "'"

const block = (b) => b.type === 'p'
  ? `LegalParagraph(${s(b.text)})`
  : `LegalBullets([${b.items.map(s).join(', ')}])`

const section = (sec) =>
  `LegalSection(${s(sec.id)}, ${s(sec.heading)}, [${sec.body.map(block).join(', ')}])`

const document = (d, effectiveDate) => `LegalDocument(
      title: ${s(d.title)},
      effectiveDate: ${s(effectiveDate)},
      effectiveDateLabel: ${s(d.effectiveDateLabel)},
      translationNotice: ${s(d.translationNotice ?? '')},
      intro: ${s(d.intro)},
      sections: [${d.sections.map(section).join(', ')}],
    )`

/** @param documents {Record<string, Record<string, object>>} doc -> locale -> content */
export function renderDart (documents, meta) {
  const docKeys = DOCS.filter((d) => documents[d])
  const body = docKeys.map((doc) => {
    const locales = LOCALES.filter((l) => documents[doc][l])
    const entries = locales
      .map((l) => `    ${s(l)}: ${document(documents[doc][l], meta[doc].effectiveDate)},`)
      .join('\n')
    return `  ${s(doc)}: {\n${entries}\n  },`
  }).join('\n')

  return `// GENERATED CODE - DO NOT MODIFY BY HAND
// Source: libs/legal-content/content/*.json
// Regenerate: node libs/legal-content/src/generate.mjs (from the repo root)
// ignore_for_file: type=lint, type=warning

import '../legal_models.dart';

/// Every legal document, keyed by LegalDoc.key then by locale tag ('pt_BR').
const Map<String, Map<String, LegalDocument>> kLegalContent = {
${body}
};
`
}
```

`libs/legal-content/src/generate.mjs`:

```js
import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { DOCS, LOCALES, repoRoot } from './constants.mjs'
import { loadDocument, loadMeta } from './schema.mjs'
import { renderDart } from './render-dart.mjs'

const write = (relPath, contents) => {
  const abs = resolve(repoRoot, relPath)
  mkdirSync(dirname(abs), { recursive: true })
  writeFileSync(abs, contents, 'utf8')
  console.log(`wrote ${relPath}`)
}

export function loadAll () {
  const documents = {}
  for (const doc of DOCS) {
    documents[doc] = {}
    for (const locale of LOCALES) documents[doc][locale] = loadDocument(doc, locale)
  }
  return documents
}

export function generate () {
  const meta = loadMeta()
  const documents = loadAll()
  write('apps/mobile/lib/features/legal/generated/legal_content.g.dart', renderDart(documents, meta))
}

generate()
```

> **Note for the implementer:** at this point `generate.mjs` only writes the Dart artifact. Task 7 adds the HTML writes to the same `generate()` function. If Task 7 lands first, merge rather than overwrite.

- [ ] **Step 5: Run the renderer test to verify it passes**

Run: `cd libs/legal-content && node --test test/render_dart.test.mjs`
Expected: PASS, 5 tests.

- [ ] **Step 6: Generate and confirm the Dart analyzes clean**

Run:
```bash
node libs/legal-content/src/generate.mjs
cd apps/mobile && flutter analyze
```
Expected: the generator prints `wrote apps/mobile/lib/features/legal/generated/legal_content.g.dart`; `flutter analyze` reports **no issues** (the repo holds a zero-warning bar).

> **Ordering, revised:** Task 8's translations run BEFORE this task, so all 33 content files already exist when the generator runs. Do **not** narrow `LOCALES` anywhere, for any reason — the generator must load all 11. If a content file is missing, that is a real failure to report, not something to work around.

- [ ] **Step 7: Commit**

```bash
git add libs/legal-content/src/render-dart.mjs libs/legal-content/src/generate.mjs \
        libs/legal-content/test/render_dart.test.mjs \
        apps/mobile/lib/features/legal/legal_doc.dart \
        apps/mobile/lib/features/legal/legal_models.dart \
        apps/mobile/lib/features/legal/generated/legal_content.g.dart
git commit -m "feat(legal): Dart renderer and generated content artifact"
```

---

### Task 7: HTML renderer and the generated web pages

Depends on Tasks 1-5, Task 8, and Task 6 (which creates `src/generate.mjs`; this task extends it). Never run concurrently with Task 6.

**Files:**
- Create: `libs/legal-content/src/render-html.mjs`
- Modify: `libs/legal-content/src/generate.mjs`
- Generate: `apps/web/{terms,privacy,faq}.html` and `apps/web/legal/{doc}.{web-tag}.html`
- Test: `libs/legal-content/test/render_html.test.mjs`

**Interfaces:**
- Consumes: `parseInline` (Task 2), `DOCS`, `LOCALES`, `webTag`.
- Produces: `renderHtml(document, {doc, locale, effectiveDate}): string`, and `pagePath(doc, locale): string` returning `terms.html` for `en` and `legal/terms.pt-BR.html` otherwise.

**Critical:** English pages land at the **repo-root-relative top level** (`apps/web/privacy.html`) because that URL is registered with Apple and Google. Non-English pages sit one directory deeper, so their asset and nav links need a `../` prefix.

- [ ] **Step 1: Write the failing test**

Create `libs/legal-content/test/render_html.test.mjs`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { renderHtml, pagePath } from '../src/render-html.mjs'

const doc = {
  doc: 'terms', locale: 'en', title: 'Terms of Service', effectiveDateLabel: 'Effective date',
  translationNotice: '', intro: 'Intro <text> & more',
  sections: [{ id: 'a', heading: 'A & B', body: [
    { type: 'p', text: 'See [the policy](privacy.html) and **note** this.' },
    { type: 'ul', items: ['one <br>', 'two'] },
  ] }],
}
const de = { ...doc, locale: 'de', translationNotice: 'Es gilt die englische Fassung.' }
const opts = (locale) => ({ doc: 'terms', locale, effectiveDate: '2026-09-08' })

test('English pages keep the top-level path', () => {
  assert.equal(pagePath('privacy', 'en'), 'privacy.html')
  assert.equal(pagePath('terms', 'en'), 'terms.html')
})

test('other locales live under legal/ with a BCP-47 tag', () => {
  assert.equal(pagePath('privacy', 'pt_BR'), 'legal/privacy.pt-BR.html')
})

test('sets lang from the locale', () => {
  assert.match(renderHtml(doc, opts('en')), /<html lang="en">/)
  assert.match(renderHtml(de, opts('de')), /<html lang="de">/)
})

test('escapes HTML-significant characters in content', () => {
  const out = renderHtml(doc, opts('en'))
  assert.ok(out.includes('Intro &lt;text&gt; &amp; more'))
  assert.ok(out.includes('A &amp; B'))
  assert.ok(out.includes('one &lt;br&gt;'))
})

test('renders inline links and bold', () => {
  const out = renderHtml(doc, opts('en'))
  assert.ok(out.includes('<a href="privacy.html">the policy</a>'))
  assert.ok(out.includes('<strong>note</strong>'))
})

test('rewrites sibling doc links for nested locale pages', () => {
  const out = renderHtml(de, opts('de'))
  assert.ok(out.includes('<a href="privacy.de.html">the policy</a>'),
    'a link to privacy.html must resolve to the same-locale page')
})

test('shows the translation notice only on non-English pages', () => {
  assert.ok(!renderHtml(doc, opts('en')).includes('translation-notice'))
  assert.ok(renderHtml(de, opts('de')).includes('Es gilt die englische Fassung.'))
})

test('emits hreflang alternates for all 11 locales plus x-default', () => {
  const out = renderHtml(doc, opts('en'))
  // 12, not 11: <link rel="alternate" hreflang="x-default"> is itself a rel="alternate".
  assert.equal((out.match(/rel="alternate"/g) || []).length, 12)
  assert.ok(out.includes('hreflang="x-default"'))
  assert.ok(out.includes('hreflang="pt-BR"'))
})

test('nested pages reach stylesheet and nav with ../', () => {
  const out = renderHtml(de, opts('de'))
  assert.ok(out.includes('href="../styles.css"'))
  assert.ok(out.includes('href="../index.html"'))
})

test('the footer links all three documents', () => {
  const out = renderHtml(doc, opts('en'))
  for (const href of ['terms.html', 'privacy.html', 'faq.html', 'support.html']) {
    assert.ok(out.includes(`href="${href}"`), `footer missing ${href}`)
  }
})

test('shows the effective date', () => {
  assert.ok(renderHtml(doc, opts('en')).includes('2026-09-08'))
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test test/render_html.test.mjs`
Expected: FAIL — `Cannot find module '../src/render-html.mjs'`.

- [ ] **Step 3: Write the implementation**

`libs/legal-content/src/render-html.mjs` — build it around these rules:

- `esc(v)` escapes `& < > "` in that order.
- `pagePath(doc, locale)` → `` `${doc}.html` `` for `en`, `` `legal/${doc}.${webTag(locale)}.html` `` otherwise.
- `prefix = locale === 'en' ? '' : '../'` for `styles.css`, `assets/icon.png`, `index.html`, `support.html`.
- A sibling-document link (`privacy.html`, `terms.html`, `faq.html`) inside content is rewritten to the **same-locale** page: for `en` it stays as-is; otherwise it becomes `` `${doc}.${webTag(locale)}.html` `` (same directory, so no prefix).
- Inline rendering maps `parseInline` tokens: `text` → escaped, `bold` → `<strong>`, `link` → `<a href="…">`. External `http(s)` links get `target="_blank" rel="noopener noreferrer"`.
- Reuse the existing site chrome verbatim — copy the `<header class="nav">` and `<footer class="footer">` markup out of `apps/web/support.html` so the generated pages match the hand-written ones, then add **Terms · Privacy · FAQ** to the footer.
- Body wrapper: `<main class="section"><div class="container prose">`, matching `privacy.html`.
- `<head>` carries `<title>{title} — ScannerCam Light</title>`, a `<meta name="description">` built from `intro` (truncated at 160 chars), and 11 `<link rel="alternate" hreflang="…">` tags plus `hreflang="x-default"` pointing at the English page.
- The language switcher is a plain `<nav class="lang-switch">` of 11 `<a>`s — **no JavaScript**, so it works with `main.js` untouched.
- **The FAQ document reuses the site's existing accordion markup**: wrap its sections in `<div class="faq">` with one `<details><summary>{heading}</summary>…</details>` per question. `styles.css` already styles `.faq`, `.faq details`, `.faq summary`, and `.faq p` (lines 98-101), so `faq.html` looks exactly like the block it replaces on `support.html`. Terms and Privacy render as plain `<h2>` + `<p>`/`<ul>` inside `.prose`, matching the current `privacy.html`.

- [ ] **Step 3b: Add the two missing CSS classes**

Everything else reuses existing styles; only these two are new. Append to `apps/web/styles.css`:

```css
/* Legal pages (generated) — language switcher and translation notice. */
.lang-switch { margin: 28px 0 0; font-size: 14px; color: var(--muted); }
.lang-switch a { display: inline-block; margin: 0 10px 6px 0; }
.lang-switch a[aria-current="page"] { font-weight: 700; text-decoration: none; }
.translation-notice {
  border-left: 3px solid var(--border);
  padding: 12px 16px;
  margin: 20px 0;
  color: var(--muted);
  font-size: 14px;
}
```

Mark the current locale's switcher link with `aria-current="page"`.

Then extend `generate()` in `src/generate.mjs`:

```js
import { renderHtml, pagePath } from './render-html.mjs'
// …inside generate(), after the Dart write:
for (const doc of DOCS) {
  for (const locale of LOCALES) {
    write(`apps/web/${pagePath(doc, locale)}`,
      renderHtml(documents[doc][locale], { doc, locale, effectiveDate: meta[doc].effectiveDate }))
  }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd libs/legal-content && node --test test/render_html.test.mjs`
Expected: PASS, 11 tests.

- [ ] **Step 5: Generate and eyeball the result**

Run:
```bash
node libs/legal-content/src/generate.mjs
cd apps/web && python3 -m http.server 8000
```
Open `http://localhost:8000/privacy.html`, `terms.html`, `faq.html`, and `legal/terms.pt-BR.html`. Confirm: site styling matches the hand-written pages, the nav and footer work from both directory depths, and the language switcher navigates correctly.

- [ ] **Step 5b: Prove the overwrite of `privacy.html` loses nothing**

This step overwrites a hand-written, currently-published page. Before accepting it, diff the old against the new:

```bash
git show HEAD:apps/web/privacy.html > /tmp/privacy-old.html
# strip tags and compare the prose, not the markup
sed -e 's/<[^>]*>//g' /tmp/privacy-old.html | tr -s ' \n' ' \n' | sort -u > /tmp/old.txt
sed -e 's/<[^>]*>//g' apps/web/privacy.html   | tr -s ' \n' ' \n' | sort -u > /tmp/new.txt
diff /tmp/old.txt /tmp/new.txt
```

Every line present in the old page and absent from the new one must be a deliberate change traceable to Task 4's content — read them one by one. If any sentence from the published policy vanished by accident, fix `privacy.en.json` and regenerate. **Do not proceed on an unreviewed diff**: this page is the URL Apple and Google point users at.

- [ ] **Step 6: Add a link-integrity check**

Create `libs/legal-content/test/links.test.mjs` asserting every `href` in every generated page that is not `mailto:`/`http` resolves to a file that exists under `apps/web/`. Run it: `node --test test/links.test.mjs` → PASS.

- [ ] **Step 7: Commit**

```bash
git add libs/legal-content/src/render-html.mjs libs/legal-content/src/generate.mjs \
        libs/legal-content/test/render_html.test.mjs libs/legal-content/test/links.test.mjs \
        apps/web/styles.css \
        apps/web/terms.html apps/web/privacy.html apps/web/faq.html apps/web/legal
git commit -m "feat(legal): HTML renderer and generated web pages"
```

---

### Task 8: The 30 translations

Depends on Tasks 3-5 (English source) only. Runs BEFORE Tasks 6 and 7. Split into three sub-tasks — **8a terms, 8b privacy, 8c faq** — each producing 10 files. Run them as three subagents.

**Files (per sub-task):**
- Create: `libs/legal-content/content/{doc}.{locale}.json` for `pt, pt_BR, es, fr, de, lb, tr, ru, zh, ar`
- Test: `libs/legal-content/test/parity.test.mjs` (written once, in 8a; 8b and 8c make it pass for their document)

**Interfaces:**
- Consumes: the English file for the document, `loadDocument`, `DOCS`, `LOCALES`.
- Produces: nothing new — the same schema, translated.

- [ ] **Step 1: Write the failing parity test** (sub-task 8a only)

Create `libs/legal-content/test/parity.test.mjs`:

```js
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { DOCS, LOCALES, repoRoot } from '../src/constants.mjs'
import { loadDocument } from '../src/schema.mjs'

test('the package locale list matches the app', () => {
  const dart = readFileSync(resolve(repoRoot, 'apps/mobile/lib/l10n/locale_resolution.dart'), 'utf8')
  // Slice out ONLY the kSupportedAppLocales list. resolveLocale() below it ends
  // with `return const Locale('en');`, which a whole-file regex would count as a
  // 12th locale — making this test impossible to pass no matter what LOCALES says.
  const block = dart.match(/kSupportedAppLocales\s*=\s*<Locale>\[([\s\S]*?)\];/)
  assert.ok(block, 'could not find kSupportedAppLocales in locale_resolution.dart')
  const tags = [...block[1].matchAll(/Locale\('([a-z]{2})'(?:,\s*'([A-Z]{2})')?\)/g)]
    .map((m) => (m[2] ? `${m[1]}_${m[2]}` : m[1]))
  assert.ok(tags.length > 0, 'locale slice matched nothing — the regex has drifted from the file')
  assert.deepEqual(tags, LOCALES)
})

for (const doc of DOCS) {
  test(`${doc}: every locale has the same section ids as English`, () => {
    const en = loadDocument(doc, 'en').sections.map((s) => s.id)
    for (const locale of LOCALES) {
      assert.deepEqual(loadDocument(doc, locale).sections.map((s) => s.id), en,
        `${doc}.${locale}.json section ids diverge from English`)
    }
  })

  test(`${doc}: every locale has the same block shape as English`, () => {
    const shape = (d) => d.sections.map((s) => s.body.map((b) => b.type + (b.type === 'ul' ? `:${b.items.length}` : '')))
    const en = shape(loadDocument(doc, 'en'))
    for (const locale of LOCALES) {
      assert.deepEqual(shape(loadDocument(doc, locale)), en, `${doc}.${locale}.json block shape diverges`)
    }
  })

  test(`${doc}: non-English documents carry the English-prevails notice`, () => {
    for (const locale of LOCALES.filter((l) => l !== 'en')) {
      const n = loadDocument(doc, locale).translationNotice
      assert.ok(n && n.trim().length > 10, `${doc}.${locale}.json has no translationNotice`)
    }
  })

  // A title-only check is not enough: a file whose title was translated but whose
  // BODY was left in English would pass every other structural assertion and ship
  // as a "translation". Compare the whole body text too.
  test(`${doc}: translations are not just copied English`, () => {
    const bodyText = (d) =>
      d.sections.map((s) => s.body.map((b) => (b.type === 'p' ? b.text : b.items.join(' '))).join(' ')).join(' ')
    const en = loadDocument(doc, 'en')
    for (const locale of LOCALES.filter((l) => l !== 'en')) {
      const other = loadDocument(doc, locale)
      assert.notEqual(other.title, en.title, `${doc}.${locale}.json title is still English`)
      assert.notEqual(other.effectiveDateLabel, en.effectiveDateLabel,
        `${doc}.${locale}.json effectiveDateLabel is still English`)
      assert.notEqual(bodyText(other), bodyText(en), `${doc}.${locale}.json body is still English`)
    }
  })

  // Section ids are keys, not prose: the Dart renderer, the HTML renderer and the
  // widget tests all key off them (`legal-section-<id>`). A translated id breaks
  // the app silently.
  test(`${doc}: section ids are never translated`, () => {
    const en = loadDocument(doc, 'en').sections.map((s) => s.id)
    for (const locale of LOCALES) {
      assert.deepEqual(loadDocument(doc, locale).sections.map((s) => s.id), en,
        `${doc}.${locale}.json has translated or reordered section ids`)
    }
  })

  // Guards a copy-paste that forgets to update the file's own identity fields.
  test(`${doc}: each file's doc and locale fields match its filename`, () => {
    for (const locale of LOCALES) {
      const d = loadDocument(doc, locale)
      assert.equal(d.doc, doc, `${doc}.${locale}.json has doc "${d.doc}"`)
      assert.equal(d.locale, locale, `${doc}.${locale}.json has locale "${d.locale}"`)
    }
  })

  // version/effectiveDate live once in meta.json; a per-locale copy would drift.
  test(`${doc}: no locale file carries a version or effective date`, () => {
    for (const locale of LOCALES) {
      const d = loadDocument(doc, locale)
      assert.equal(d.version, undefined, `${doc}.${locale}.json must not carry a version`)
      assert.equal(d.effectiveDate, undefined, `${doc}.${locale}.json must not carry an effectiveDate`)
    }
  })

  test(`${doc}: the support email survives translation`, () => {
    for (const locale of LOCALES) {
      assert.match(JSON.stringify(loadDocument(doc, locale)), /scannercamlight\.line149@passmail\.net/)
    }
  })

  test(`${doc}: inline link targets are identical across locales`, () => {
    const urls = (d) => [...JSON.stringify(d).matchAll(/\]\(([^)\s]+)\)/g)].map((m) => m[1]).sort()
    const en = urls(loadDocument(doc, 'en'))
    for (const locale of LOCALES) {
      assert.deepEqual(urls(loadDocument(doc, locale)), en, `${doc}.${locale}.json link targets diverge`)
    }
  })
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd libs/legal-content && node --test test/parity.test.mjs`
Expected: FAIL — `ENOENT ... content/terms.pt.json`.

- [ ] **Step 3: Write the 10 translations for this sub-task's document**

Rules, non-negotiable:
- **Identical structure.** Same `sections` ids, same order, same block types, same `ul` item counts. The parity test enforces this.
- **Identical link targets.** `[label](url)` labels are translated; `url` values are not.
- **`translationNotice` is required**, saying in that language: "This translation is provided for convenience. If it conflicts with the English version, the English version prevails." Include a `[label](terms.html)`-style link to the English page only if the English document has one in the same position — otherwise plain text.
- **`title` and `effectiveDateLabel` are translated.**
- `ar` content is written right-to-left in natural Arabic; do not add directional control characters — Flutter and the browser derive direction from the locale.
- `lb` is Luxembourgish, `pt` is European Portuguese, `pt_BR` Brazilian, `zh` Simplified Chinese.

- [ ] **Step 4: Run the parity test to verify it passes**

Run: `cd libs/legal-content && node --test`
Expected: PASS. (Sub-tasks 8b and 8c will still fail their own document's parity assertions until they land — that is expected while they run in parallel; the full suite is green only after all three.)

- [ ] **Step 5: Commit**

```bash
git add libs/legal-content/content/<doc>.*.json libs/legal-content/test/parity.test.mjs
git commit -m "feat(legal): <doc> translations for the 10 non-English locales"
```

---

### Task 9: Dart inline parser

Depends on Task 2 (token shape) and Task 6 (`legal_models.dart` exists). Parallel with Task 10.

**Files:**
- Create: `apps/mobile/lib/features/legal/legal_inline.dart`
- Test: `apps/mobile/test/features/legal/legal_inline_test.dart`

**Interfaces:**
- Consumes: nothing.
- Produces: `class LegalInlineSpan { final String text; final bool bold; final String? url; }` and `List<LegalInlineSpan> parseLegalInline(String text)` — the exact behavioural mirror of `parseInline` in `libs/legal-content/src/inline.mjs`. The test cases below are the JS fixtures from Task 2, translated.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/legal/legal_inline_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_inline.dart';

void main() {
  test('plain text is one span', () {
    final spans = parseLegalInline('hello world');
    expect(spans.length, 1);
    expect(spans.single.text, 'hello world');
    expect(spans.single.bold, isFalse);
    expect(spans.single.url, isNull);
  });

  test('bold in the middle splits into three spans', () {
    final spans = parseLegalInline('a **b** c');
    expect(spans.map((s) => s.text).toList(), ['a ', 'b', ' c']);
    expect(spans.map((s) => s.bold).toList(), [false, true, false]);
  });

  test('a link keeps its label and url', () {
    final spans = parseLegalInline('see [the policy](privacy.html) now');
    expect(spans.map((s) => s.text).toList(), ['see ', 'the policy', ' now']);
    expect(spans[1].url, 'privacy.html');
    expect(spans[0].url, isNull);
  });

  test('bold and link coexist', () {
    final spans = parseLegalInline('**Note:** mail [us](mailto:a@b.c)');
    expect(spans.map((s) => s.text).toList(), ['Note:', ' mail ', 'us']);
    expect(spans[0].bold, isTrue);
    expect(spans[2].url, 'mailto:a@b.c');
  });

  test('an unmatched asterisk pair stays literal', () {
    final spans = parseLegalInline('2 ** 3');
    expect(spans.single.text, '2 ** 3');
  });

  test('empty string yields no spans', () {
    expect(parseLegalInline(''), isEmpty);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/legal/legal_inline_test.dart`
Expected: FAIL — `Error: Couldn't resolve the package 'mobile/features/legal/legal_inline.dart'`.

- [ ] **Step 3: Write the implementation**

`apps/mobile/lib/features/legal/legal_inline.dart`:

```dart
/// One run of inline text from a legal document: plain, bold, or a link.
class LegalInlineSpan {
  final String text;
  final bool bold;
  final String? url;
  const LegalInlineSpan(this.text, {this.bold = false, this.url});
}

// Must stay behaviourally identical to parseInline() in
// libs/legal-content/src/inline.mjs — the two suites share fixtures.
final _pattern = RegExp(r'\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]+)\)');

/// Splits [text] into spans. Only `**bold**` and `[label](url)` are markup;
/// anything else is literal.
List<LegalInlineSpan> parseLegalInline(String text) {
  final spans = <LegalInlineSpan>[];
  var last = 0;
  for (final m in _pattern.allMatches(text)) {
    if (m.start > last) spans.add(LegalInlineSpan(text.substring(last, m.start)));
    if (m.group(1) != null) {
      spans.add(LegalInlineSpan(m.group(1)!, bold: true));
    } else {
      spans.add(LegalInlineSpan(m.group(2)!, url: m.group(3)));
    }
    last = m.end;
  }
  if (last < text.length) spans.add(LegalInlineSpan(text.substring(last)));
  return spans;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/legal/legal_inline_test.dart`
Expected: PASS, 6 tests.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/legal/legal_inline.dart \
        apps/mobile/test/features/legal/legal_inline_test.dart
git commit -m "feat(legal): Dart inline markup parser mirroring the JS one"
```

---

### Task 10: `legalDocument()` lookup with English fallback

Depends on Task 6 (generated artifact + models). Parallel with Task 9.

**Files:**
- Create: `apps/mobile/lib/features/legal/legal_content.dart`
- Test: `apps/mobile/test/features/legal/legal_content_test.dart`

**Interfaces:**
- Consumes: `kLegalContent` (generated), `LegalDoc`, `LegalDocument`, `localeTag` from `package:mobile/l10n/locale_store.dart`.
- Produces: `LegalDocument legalDocument(LegalDoc doc, Locale locale)`. **This is the only file allowed to import `generated/legal_content.g.dart`.**

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/legal/legal_content_test.dart`:

```dart
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_content.dart';
import 'package:mobile/features/legal/legal_doc.dart';
import 'package:mobile/l10n/locale_resolution.dart';

void main() {
  test('returns the English document for en', () {
    final d = legalDocument(LegalDoc.terms, const Locale('en'));
    expect(d.title, 'Terms of Service');
    expect(d.translationNotice, isEmpty);
    expect(d.sections, isNotEmpty);
  });

  test('returns a translated document with a notice for a non-English locale', () {
    final d = legalDocument(LegalDoc.terms, const Locale('de'));
    expect(d.title, isNot('Terms of Service'));
    expect(d.translationNotice, isNotEmpty);
  });

  test('distinguishes pt from pt_BR', () {
    final pt = legalDocument(LegalDoc.faq, const Locale('pt'));
    final br = legalDocument(LegalDoc.faq, const Locale('pt', 'BR'));
    expect(pt.sections.length, br.sections.length);
  });

  test('falls back to English for an unsupported locale', () {
    final d = legalDocument(LegalDoc.privacy, const Locale('ja'));
    expect(d.title, legalDocument(LegalDoc.privacy, const Locale('en')).title);
  });

  test('falls back to the base language when the country is unknown', () {
    final d = legalDocument(LegalDoc.privacy, const Locale('pt', 'AO'));
    expect(d.title, legalDocument(LegalDoc.privacy, const Locale('pt')).title);
  });

  test('every document exists in every supported locale', () {
    for (final doc in LegalDoc.values) {
      for (final locale in kSupportedAppLocales) {
        final d = legalDocument(doc, locale);
        expect(d.sections, isNotEmpty, reason: '$doc/$locale is empty');
        expect(d.effectiveDate, isNotEmpty);
      }
    }
  });

  test('all locales of a document share the same section ids', () {
    for (final doc in LegalDoc.values) {
      final en = legalDocument(doc, const Locale('en')).sections.map((s) => s.id).toList();
      for (final locale in kSupportedAppLocales) {
        expect(legalDocument(doc, locale).sections.map((s) => s.id).toList(), en,
            reason: '$doc/$locale diverges from English');
      }
    }
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/legal/legal_content_test.dart`
Expected: FAIL — cannot resolve `legal_content.dart`.

- [ ] **Step 3: Write the implementation**

`apps/mobile/lib/features/legal/legal_content.dart`:

```dart
import 'dart:ui';

import '../../l10n/locale_store.dart' show localeTag;
import 'generated/legal_content.g.dart';
import 'legal_doc.dart';
import 'legal_models.dart';

/// The document [doc] in [locale].
///
/// Resolution order: exact tag ('pt_BR'), then the base language ('pt'), then
/// English. English always exists, so this never returns null — a missing
/// translation degrades to a readable document rather than an empty screen.
LegalDocument legalDocument(LegalDoc doc, Locale locale) {
  final byLocale = kLegalContent[doc.key]!;
  return byLocale[localeTag(locale)] ??
      byLocale[locale.languageCode] ??
      byLocale['en']!;
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/legal/legal_content_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/legal/legal_content.dart \
        apps/mobile/test/features/legal/legal_content_test.dart
git commit -m "feat(legal): document lookup with locale fallback"
```

---

### Task 11: `LegalDocumentScreen`

Depends on Tasks 9 and 10.

**Files:**
- Create: `apps/mobile/lib/features/legal/legal_document_screen.dart`
- Test: `apps/mobile/test/features/legal/legal_document_screen_test.dart`

**Interfaces:**
- Consumes: `legalDocument`, `parseLegalInline`, `LegalDoc`, `LegalParagraph`, `LegalBullets`, `AppBackHeader`, `context.appColors`, `AppTypography`.
- Produces: `class LegalDocumentScreen extends StatelessWidget` with `const LegalDocumentScreen({super.key, required this.doc, this.openUrl = _launchExternal})` and `static Route<void> route(LegalDoc doc, {LegalUrlOpener? openUrl})`. `typedef LegalUrlOpener = Future<bool> Function(Uri uri)` — the same injectable seam shape as `DonationUrlOpener` in `donation_screen.dart`, so link taps are testable without the platform channel.

Rendering rules: `AppBackHeader(title: document.title)`; then the effective date (`'$effectiveDateLabel: $effectiveDate'`), the translation notice when non-empty, the intro, then the sections. `LegalDoc.faq` renders sections as `ExpansionTile`s (`heading` = title, `body` = children); `terms` and `privacy` render heading + blocks flat.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/legal/legal_document_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/legal/legal_content.dart';
import 'package:mobile/features/legal/legal_doc.dart';
import 'package:mobile/features/legal/legal_document_screen.dart';

import '../../support/localized_app.dart';

Widget _host(LegalDoc doc, {Locale locale = const Locale('en'), List<Uri>? opened}) =>
    localizedTestApp(
      locale: locale,
      home: LegalDocumentScreen(
        doc: doc,
        openUrl: (uri) async {
          opened?.add(uri);
          return true;
        },
      ),
    );

void main() {
  testWidgets('shows the document title in the header', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    expect(find.text('Terms of Service'), findsOneWidget);
  });

  testWidgets('shows the effective date', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    expect(find.textContaining('2026-09-08'), findsOneWidget);
  });

  testWidgets('renders every section heading of the terms', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    final doc = legalDocument(LegalDoc.terms, const Locale('en'));
    // Scroll through so off-screen headings are built.
    for (final section in doc.sections) {
      await t.scrollUntilVisible(find.text(section.heading), 300);
      expect(find.text(section.heading), findsOneWidget);
    }
  });

  testWidgets('hides the translation notice in English', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms));
    expect(find.byKey(const Key('legal-translation-notice')), findsNothing);
  });

  testWidgets('shows the translation notice in German', (t) async {
    await t.pumpWidget(_host(LegalDoc.terms, locale: const Locale('de')));
    expect(find.byKey(const Key('legal-translation-notice')), findsOneWidget);
  });

  testWidgets('the FAQ renders collapsed questions that expand on tap', (t) async {
    await t.pumpWidget(_host(LegalDoc.faq));
    final doc = legalDocument(LegalDoc.faq, const Locale('en'));
    final first = doc.sections.first;
    final answer = (first.body.first as dynamic).text as String;
    expect(find.text(first.heading), findsOneWidget);
    expect(find.textContaining(answer.substring(0, 12)), findsNothing);
    await t.tap(find.text(first.heading));
    await t.pumpAndSettle();
    expect(find.textContaining(answer.substring(0, 12)), findsOneWidget);
  });

  testWidgets('tapping an inline link opens it through the injected opener', (t) async {
    final opened = <Uri>[];
    await t.pumpWidget(_host(LegalDoc.terms, opened: opened));
    await t.scrollUntilVisible(find.byKey(const Key('legal-section-contact')), 300);
    await t.tap(find.textContaining('scannercamlight.line149@passmail.net').first);
    await t.pumpAndSettle();
    expect(opened.single.scheme, 'mailto');
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/legal/legal_document_screen_test.dart`
Expected: FAIL — cannot resolve `legal_document_screen.dart`.

- [ ] **Step 3: Write the implementation**

Build `legal_document_screen.dart` following the conventions in `donation_screen.dart` and `settings_screen.dart`:

- Scaffold `backgroundColor: r.paper`, `appBar: AppBackHeader(title: document.title, onBack: () => Navigator.of(context).maybePop())`.
- Body is a `ListView` with `padding: const EdgeInsets.all(20)`.
- Give each section a `Key('legal-section-${section.id}')`.
- Give the translation-notice widget `Key('legal-translation-notice')` and render it in a `r.amberSoft` container.
- Paragraphs render as `RichText`/`Text.rich` built from `parseLegalInline`, with bold spans at `FontWeight.w700` and link spans in `r.blue` + `TapGestureRecognizer` calling `openUrl(Uri.parse(url))`. **Dispose every recognizer** — build them in a `StatefulWidget` (`_LegalParagraph`) that disposes in `dispose()`, or the widget test will report leaked gesture recognizers.
- Bullets render as a `Column` of `Row`s with a `•` prefix.
- Body text: `fontFamily: 'Figtree'`, `fontSize: 14.5`, `height: 1.55`, `color: r.ink2`. Headings: `fontSize: 16`, `FontWeight.w700`, `color: r.ink`.
- `route()`:

```dart
  static Route<void> route(LegalDoc doc, {LegalUrlOpener? openUrl}) =>
      MaterialPageRoute<void>(
        builder: (_) => openUrl == null
            ? LegalDocumentScreen(doc: doc)
            : LegalDocumentScreen(doc: doc, openUrl: openUrl),
      );
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/legal/legal_document_screen_test.dart`
Expected: PASS, 7 tests.

- [ ] **Step 5: Confirm no analyzer regression**

Run: `cd apps/mobile && flutter analyze`
Expected: **No issues found.**

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/legal/legal_document_screen.dart \
        apps/mobile/test/features/legal/legal_document_screen_test.dart
git commit -m "feat(legal): document screen with FAQ accordion and inline links"
```

---

### Task 12: Settings integration

Depends on Task 11.

**Files:**
- Modify: `apps/mobile/lib/features/settings/settings_screen.dart`
- Modify: `apps/mobile/lib/l10n/app_en.arb` and the 10 others
- Modify: `apps/mobile/lib/features/library/feature_flags.dart` (doc comment only)
- Test: `apps/mobile/test/features/settings/settings_screen_test.dart` (extend)

**Interfaces:**
- Consumes: `LegalDocumentScreen.route`, `LegalDoc`, `legalDocument`.
- Produces: three tappable rows keyed `settings-terms`, `settings-privacy`, `settings-faq`.

- [ ] **Step 1: Write the failing test**

Append to `apps/mobile/test/features/settings/settings_screen_test.dart`:

```dart
  testWidgets('shows a Legal section with all three documents', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.scrollUntilVisible(find.byKey(const Key('settings-terms')), 300);
    expect(find.byKey(const Key('settings-terms')), findsOneWidget);
    expect(find.byKey(const Key('settings-privacy')), findsOneWidget);
    expect(find.byKey(const Key('settings-faq')), findsOneWidget);
    expect(find.text('LEGAL'), findsOneWidget); // AppSectionLabel upper-cases
  });

  testWidgets('the legal rows are labelled from the content package', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.scrollUntilVisible(find.byKey(const Key('settings-terms')), 300);
    expect(find.text('Terms of Service'), findsOneWidget);
    expect(find.text('Privacy Policy'), findsOneWidget);
    expect(find.text('Frequently Asked Questions'), findsOneWidget);
  });

  testWidgets('the terms row opens the terms document', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.scrollUntilVisible(find.byKey(const Key('settings-terms')), 300);
    await t.tap(find.byKey(const Key('settings-terms')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('legal-section-acceptance')), findsOneWidget);
  });

  testWidgets('the privacy row opens the privacy document', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.scrollUntilVisible(find.byKey(const Key('settings-privacy')), 300);
    await t.tap(find.byKey(const Key('settings-privacy')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('legal-section-summary')), findsOneWidget);
  });

  testWidgets('the faq row opens the faq document', (t) async {
    final c = ThemeController(store: InMemoryThemeModeStore());
    await t.pumpWidget(_host(c));
    await t.scrollUntilVisible(find.byKey(const Key('settings-faq')), 300);
    await t.tap(find.byKey(const Key('settings-faq')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('legal-section-offline')), findsOneWidget);
  });
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/settings/settings_screen_test.dart`
Expected: FAIL — the five new tests fail on `findsNothing` for `settings-terms`; the pre-existing tests still pass.

- [ ] **Step 3: Add the ARB key to all 11 files**

In `apps/mobile/lib/l10n/app_en.arb`, beside `settingsSectionFeedback`:

```json
  "settingsSectionLegal": "Legal",
  "@settingsSectionLegal": {
    "description": "Settings section heading above the Terms, Privacy and FAQ rows"
  },
```

Add `"settingsSectionLegal"` with the translated word to each of the other 10 (`Jurídico` pt/pt_BR, `Legal` es, `Mentions légales` fr, `Rechtliches` de, `Rechtleches` lb, `Yasal` tr, `Правовая информация` ru, `法律信息` zh, `الشؤون القانونية` ar). Only translated files carry the value — the `@` metadata block lives in `app_en.arb` only, matching the existing convention.

Run: `cd apps/mobile && flutter test test/l10n/arb_parity_test.dart`
Expected: PASS — parity holds across all 11.

- [ ] **Step 4: Add the section to the settings screen**

In `settings_screen.dart`, add the imports:

```dart
import '../legal/legal_content.dart';
import '../legal/legal_doc.dart';
import '../legal/legal_document_screen.dart';
```

and insert between the feedback/support block and `const SizedBox(height: 36)`:

```dart
            const SizedBox(height: 28),
            AppSectionLabel(context.l10n.settingsSectionLegal),
            const SizedBox(height: 10),
            for (final entry in const [
              (LegalDoc.terms, 'settings-terms', Icons.gavel_outlined),
              (LegalDoc.privacy, 'settings-privacy', Icons.lock_outline),
              (LegalDoc.faq, 'settings-faq', Icons.help_outline),
            ])
              _NavRow(
                key: Key(entry.$2),
                icon: entry.$3,
                // Row labels come from the content package, not ARB, so the
                // app and the website always show the same document names.
                label: legalDocument(
                  entry.$1,
                  Localizations.localeOf(context),
                ).title,
                onTap: () => Navigator.of(
                  context,
                ).push(LegalDocumentScreen.route(entry.$1)),
              ),
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/settings/settings_screen_test.dart`
Expected: PASS — all pre-existing tests plus the five new ones.

- [ ] **Step 6: Document the deliberate no-flag exception**

In `feature_flags.dart`, extend the class doc comment with:

```
/// DELIBERATE EXCEPTION: the Legal section in Settings (Terms, Privacy, FAQ)
/// carries no flag. Apple and Google both require the privacy policy to be
/// reachable from inside the app, so a build that could hide it is a
/// store-rejection risk, not a feature.
```

- [ ] **Step 7: Run the full host suite — nothing else may break**

Run: `cd apps/mobile && flutter test`
Expected: PASS, zero failures. Compare the total against the pre-change baseline; the count should rise by the new tests only.

Run: `cd apps/mobile && flutter analyze`
Expected: **No issues found.**

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/settings/settings_screen.dart \
        apps/mobile/lib/features/library/feature_flags.dart \
        apps/mobile/lib/l10n/app_*.arb \
        apps/mobile/test/features/settings/settings_screen_test.dart
git commit -m "feat(legal): Legal section in Settings linking all three documents"
```

---

### Task 13: BDD feature and steps

Depends on Task 12.

**Files:**
- Create: `apps/mobile/test/bdd/legal_documents.feature`
- Create: `apps/mobile/test/step/i_open_the_terms_of_service.dart`
- Create: `apps/mobile/test/step/i_open_the_privacy_policy.dart`
- Create: `apps/mobile/test/step/i_open_the_faq.dart`
- Create: `apps/mobile/test/step/i_expand_the_first_question.dart`
- Create: `apps/mobile/test/step/the_document_disclaims_all_warranties.dart`
- Create: `apps/mobile/test/step/the_document_says_i_am_responsible_for_what_i_scan.dart`
- Create: `apps/mobile/test/step/the_document_warns_that_feedback_is_public.dart`
- Create: `apps/mobile/test/step/the_answer_is_shown.dart`
- Create: `apps/mobile/test/step/the_english_prevails_notice_is_shown.dart`
- Generated: `apps/mobile/test/bdd/legal_documents_test.dart`

**Interfaces:**
- Consumes: the existing steps `the app is launched with empty storage and mocked preferences`, `I open settings from home`, `I choose the Spanish language`.
- Produces: nothing other tasks consume.

- [ ] **Step 1: Write the feature file**

`apps/mobile/test/bdd/legal_documents.feature`:

```gherkin
Feature: Legal documents

  Terms of Service, Privacy Policy and FAQ are readable from Settings, offline,
  in the user's own language. Translations carry a notice that the English
  version prevails.

  Scenario: The terms disclaim liability and place responsibility on the user
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I open the terms of service
    Then the document disclaims all warranties
    And the document says I am responsible for what I scan

  Scenario: The privacy policy warns that feedback is public
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I open the privacy policy
    Then the document warns that feedback is public

  Scenario: FAQ answers are hidden until a question is tapped
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I open the faq
    And I expand the first question
    Then the answer is shown

  Scenario: A translated document says the English version prevails
    Given the app is launched with empty storage and mocked preferences
    When I open settings from home
    And I choose the Spanish language
    And I open the terms of service
    Then the English prevails notice is shown
```

- [ ] **Step 2: Generate and run to verify it fails**

Run:
```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs
flutter test test/bdd/legal_documents_test.dart
```
Expected: FAIL — the generated test imports step files that do not exist yet (compile error naming the missing steps).

- [ ] **Step 3: Write the step implementations**

Each follows the existing `test/step/` convention — a single `Future<void> stepName(WidgetTester tester)`. Examples:

```dart
// test/step/i_open_the_terms_of_service.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the terms of service
Future<void> iOpenTheTermsOfService(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const Key('settings-terms')), 300);
  await tester.tap(find.byKey(const Key('settings-terms')));
  await tester.pumpAndSettle();
}
```

```dart
// test/step/the_document_disclaims_all_warranties.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the document disclaims all warranties
Future<void> theDocumentDisclaimsAllWarranties(WidgetTester tester) async {
  await tester.scrollUntilVisible(
    find.byKey(const Key('legal-section-no-warranty')),
    300,
  );
  expect(find.byKey(const Key('legal-section-no-warranty')), findsOneWidget);
  expect(find.textContaining('as is'), findsWidgets);
}
```

```dart
// test/step/the_english_prevails_notice_is_shown.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the English prevails notice is shown
Future<void> theEnglishPrevailsNoticeIsShown(WidgetTester tester) async {
  expect(find.byKey(const Key('legal-translation-notice')), findsOneWidget);
}
```

Write the remaining six in the same shape: `i_open_the_privacy_policy` and `i_open_the_faq` tap their keys; `the_document_says_i_am_responsible_for_what_i_scan` scrolls to `legal-section-your-content` and asserts text containing `solely responsible`; `the_document_warns_that_feedback_is_public` scrolls to `legal-section-feedback` and asserts text containing `public`; `i_expand_the_first_question` taps the first `ExpansionTile`; `the_answer_is_shown` asserts the expanded body text is findable.

- [ ] **Step 4: Run the BDD test to verify it passes**

Run: `cd apps/mobile && flutter test test/bdd/legal_documents_test.dart`
Expected: PASS, 4 scenarios.

- [ ] **Step 5: Run the whole host suite**

Run: `cd apps/mobile && flutter test`
Expected: PASS, zero failures. Regenerating with `build_runner` touches other generated tests — confirm none regressed.

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/test/bdd/legal_documents.feature \
        apps/mobile/test/bdd/legal_documents_test.dart \
        apps/mobile/test/step/
git commit -m "test(legal): BDD scenarios for the three documents"
```

---

### Task 14: Website chrome — footers, de-duplicated FAQ, accurate claims

Depends on Task 7 (generated pages exist).

**Files:**
- Modify: `apps/web/index.html`
- Modify: `apps/web/support.html`
- Modify: `apps/web/README.md`
- Modify: `.github/workflows/pages.yml`

**Interfaces:** none — hand-edited pages only. **Do not touch the generated pages here**; they come from the renderer.

- [ ] **Step 1: Add Terms and FAQ to both hand-written footers**

In `index.html` and `support.html`, replace the footer link row with:

```html
        <a href="terms.html">Terms</a> &nbsp;·&nbsp;
        <a href="privacy.html">Privacy</a> &nbsp;·&nbsp;
        <a href="faq.html">FAQ</a> &nbsp;·&nbsp;
        <a href="support.html">Support</a> &nbsp;·&nbsp;
        <a href="index.html#donate">Donate</a> &nbsp;·&nbsp;
        <a href="mailto:scannercamlight.line149@passmail.net">Contact</a>
```

(In `index.html` the Donate link stays `#donate`.) The generated pages already carry this footer from Task 7 — make the wording identical so the site reads as one.

- [ ] **Step 2: Replace `support.html`'s inline FAQ with a pointer**

Delete the whole `<div class="faq">…</div>` block and its `<h2>Frequently asked questions</h2>`, and put in their place:

```html
      <h2>Frequently asked questions</h2>
      <p>Answers to the most common questions — offline use, where your files live, exports, tips, and what happens to feedback — are on the <a href="faq.html">FAQ page</a>.</p>
```

This removes the duplicate: `faq.html` is now the only FAQ, generated from the shared package.

- [ ] **Step 3: Make the privacy claims on `index.html` precise**

Replace the privacy-section lead:

```html
          <p class="lead">The released Android build does not request the <code>INTERNET</code> permission at all, and the app bundles no analytics on either platform. Scanning, OCR, and storage all happen on your device.</p>
```

Change the fourth check from `Free to use` to `Free, with an optional tip`, and the hero badge `💸 Free` to `💸 Free, tip optional`. Add a Terms link beside the existing privacy link:

```html
        <p style="margin-top:24px"><a href="privacy.html">Read the full privacy policy →</a> &nbsp;·&nbsp; <a href="terms.html">Terms of Service →</a></p>
```

- [ ] **Step 4: Update the site README**

In `apps/web/README.md`, add `terms.html`, `faq.html`, and `legal/` to the Pages list, and add a line stating these are **generated** by `node libs/legal-content/src/generate.mjs` (run from the repo root) and must not be hand-edited.

- [ ] **Step 5: Keep the deploy trigger honest**

In `.github/workflows/pages.yml`, add to the `paths:` filter under `on.push`:

```yaml
      - 'libs/legal-content/**'
```

so regenerating content redeploys the site. **Change nothing else in this file** — the upload-`apps/web`-verbatim mechanism must stay as it is.

- [ ] **Step 6: Verify the site by hand**

Run: `cd apps/web && python3 -m http.server 8000`
Click through `index.html` → Terms, Privacy, FAQ, Support, and from a generated page back to the hand-written ones, in both directions and from `legal/terms.pt-BR.html`. Every link must resolve; no 404s.

Run: `cd libs/legal-content && node --test test/links.test.mjs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add apps/web/index.html apps/web/support.html apps/web/README.md .github/workflows/pages.yml
git commit -m "feat(web): link Terms/Privacy/FAQ site-wide and de-duplicate the FAQ"
```

---

### Task 15: Drift guard script and CI

Depends on Tasks 6, 7, 8.

**Files:**
- Create: `scripts/check-legal-content.sh`
- Create: `.github/workflows/legal-content.yml`
- Create: `libs/legal-content/README.md`

**Interfaces:**
- Consumes: `node libs/legal-content/src/generate.mjs` (run from the repo root).
- Produces: a script that exits non-zero when committed outputs differ from freshly generated ones.

- [ ] **Step 1: Write the failing check**

Create `scripts/check-legal-content.sh`, modelled on `scripts/check-theme-tokens.sh`:

```bash
#!/usr/bin/env bash
# Fails if the committed legal artifacts differ from what the generator
# produces. The generated Dart and the 33 web pages are committed (Pages
# uploads apps/web verbatim, with no build step), so this is what stops the
# app and the website from drifting apart.
set -euo pipefail

cd "$(dirname "$0")/.."

OUTPUTS=(
  "apps/mobile/lib/features/legal/generated/legal_content.g.dart"
  "apps/web/terms.html"
  "apps/web/privacy.html"
  "apps/web/faq.html"
  "apps/web/legal"
)

# Invoke node directly rather than through `pnpm --filter ... <script>`: pnpm 11's
# verifyDepsBeforeRun spawns an inner `pnpm install` that fails in some local
# environments (it does on this repo's dev machine, for every workspace package,
# including ones this work never touched). Calling node keeps the guard identical
# locally and in CI.
echo "==> Running the content test suite"
( cd libs/legal-content && node --test )

echo "==> Regenerating legal artifacts"
( cd libs/legal-content && node src/generate.mjs )

echo "==> Checking for drift"
# Untracked files matter as much as modified ones: `git diff` is blind to a
# brand-new apps/web/legal/*.html that was generated but never committed.
UNTRACKED="$(git ls-files --others --exclude-standard -- "${OUTPUTS[@]}")"
if [ -n "$UNTRACKED" ]; then
  echo
  echo "FAIL: generated legal content includes files that were never committed:"
  echo "$UNTRACKED"
  echo "Fix: git add them, or delete them if they are no longer generated."
  exit 1
fi

if ! git diff --quiet -- "${OUTPUTS[@]}"; then
  echo
  echo "FAIL: generated legal content is out of date."
  echo "Someone edited a generated file by hand, or edited content/ without regenerating."
  echo "Fix: node libs/legal-content/src/generate.mjs (from the repo root), then commit the result."
  echo
  git diff --stat -- "${OUTPUTS[@]}"
  exit 1
fi

echo "OK: legal content is in sync (3 documents x 11 locales)."
```

- [ ] **Step 2: Prove the guard actually catches drift**

Run:
```bash
chmod +x scripts/check-legal-content.sh
bash scripts/check-legal-content.sh                 # expect OK

# Case 1: a hand edit to a committed generated file
printf '\n<!-- hand edit -->\n' >> apps/web/terms.html
bash scripts/check-legal-content.sh                 # expect FAIL, exit 1
git checkout -- apps/web/terms.html
bash scripts/check-legal-content.sh                 # expect OK again

# Case 2: a generated file that was never committed (git diff is blind to this)
cp apps/web/legal/terms.de.html apps/web/legal/terms.zz.html
bash scripts/check-legal-content.sh                 # expect FAIL, exit 1
rm apps/web/legal/terms.zz.html
bash scripts/check-legal-content.sh                 # expect OK again
```
Expected: OK, FAIL, OK, FAIL, OK. **Both** failure cases must be proven — a guard that only catches modifications misses the newly-generated-but-uncommitted file entirely. A guard that never fails is not a guard; do not skip this step.

- [ ] **Step 3: Wire it into CI**

Create `.github/workflows/legal-content.yml`:

```yaml
name: Legal content

# The generated Dart and the 33 web pages are committed. This job proves they
# still match libs/legal-content/content/, so the app and the site cannot drift.
on:
  push:
    branches: [master]
    paths:
      - 'libs/legal-content/**'
      - 'apps/web/**'
      - 'apps/mobile/lib/features/legal/**'
      - '.github/workflows/legal-content.yml'
  pull_request:
    paths:
      - 'libs/legal-content/**'
      - 'apps/web/**'
      - 'apps/mobile/lib/features/legal/**'
  workflow_dispatch:

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: pnpm
      - run: pnpm install --frozen-lockfile
      - run: bash scripts/check-legal-content.sh
```

- [ ] **Step 4: Write the package README**

`libs/legal-content/README.md`: what the package is, that `content/` is the only hand-edited directory, that both output sets are generated and committed, the regenerate command, how to add a locale (add it to `LOCALES`, add 3 files, regenerate), and a warning that `apps/web/privacy.html`'s URL is registered with Apple and Google and must not move.

- [ ] **Step 5: Run the guard one final time**

Run: `bash scripts/check-legal-content.sh`
Expected: `OK: legal content is in sync (3 documents x 11 locales).`

- [ ] **Step 6: Commit**

```bash
git add scripts/check-legal-content.sh .github/workflows/legal-content.yml libs/legal-content/README.md
git commit -m "ci(legal): guard against app/web legal-content drift"
```

---

### Task 16: Device verification on real Android and real iOS

Depends on every prior task. **This is the task that decides whether the work is done** — `CLAUDE.md` forbids calling it done on host-green alone.

**Files:**
- Create: `apps/mobile/integration_test/legal_documents_device_test.dart`

**Interfaces:**
- Consumes: `runCamScannerApp` from `main.dart`, `LegalDoc`, the settings keys from Task 12.

- [ ] **Step 1: Write the device test**

`apps/mobile/integration_test/legal_documents_device_test.dart` — launch the app, open Settings, and for each of the three documents: tap its row, assert its first section key renders, scroll to the last section, and pop back. Then switch the language to Spanish and assert `legal-translation-notice` appears. Follow the binding/launch pattern of an existing device test such as `integration_test/b2_restart_persistence_test.dart`.

- [ ] **Step 2: List the attached devices**

Run: `cd apps/mobile && flutter devices`
Record the real Android device id and the real iOS device id. A simulator is **not** sufficient for the claim; if only a simulator is available, say so explicitly rather than reporting the run as device-verified.

- [ ] **Step 3: Run on the real Android device**

Run: `cd apps/mobile && flutter test integration_test/legal_documents_device_test.dart -d <android-device-id>`
Expected: PASS. Paste the output.

- [ ] **Step 4: Run on the real iOS device**

Run: `cd apps/mobile && flutter test integration_test/legal_documents_device_test.dart -d <ios-device-id>`
Expected: PASS. Paste the output.

- [ ] **Step 5: Check the Arabic RTL rendering by hand**

Run the app on one device, set the language to العربية, and open each document. Confirm the text is right-aligned, the back chevron mirrors, and nothing overflows. Screenshot each. RTL layout is the failure mode the widget tests cannot catch.

- [ ] **Step 6: Full host suite and analyzer, one last time**

Run:
```bash
cd apps/mobile && flutter test && flutter analyze
cd /Users/pablohpsilva/Documents/camscanner-light && bash scripts/check-legal-content.sh
```
Expected: all green, zero analyzer issues, content in sync.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/integration_test/legal_documents_device_test.dart
git commit -m "test(legal): device integration test for the three documents"
```

---

## Execution order

**Revised after the pre-flight conflict scan.** Two corrections to the original ordering: the generator loads all 11 locales unconditionally, so the translations must exist before it ever runs; and Tasks 6 and 7 both write `src/generate.mjs`, so they were never independent.

```
Task 1 ─┬─> Task 3 ─┐
        ├─> Task 4 ─┼─> Task 8a/8b/8c ─> Task 6 ─> Task 7 ─┬─> Task 14 ──────────────┐
        └─> Task 5 ─┘                                      ├─> Task 15 ──────────────┤
Task 2 ─────────────────────────────────> Task 9 ─┐        │                         ├─> Task 16
                                          Task 10 ┴────────┴─> Task 11 ─> 12 ─> 13 ──┘
```

Dependency order:
- **Group 1:** Task 1, Task 2 (independent of each other)
- **Group 2:** Tasks 3, 4, 5 (independent, all need Task 1)
- **Group 3:** Tasks 8a, 8b, 8c (independent, need only the English content)
- **Group 4:** Task 6, then Task 7 — **strictly serial, same file**
- **Group 5:** Tasks 9, 10, 14 (independent)
- **Group 6:** Task 11 → 12 → 13 (a genuine chain), Task 15
- **Group 7:** Task 16 (device verification, serial by nature)

**On concurrency:** these groups express *dependency*, not a mandate to run concurrently. Every task commits into one working tree with one git index, so concurrent implementers would interleave commits and corrupt each other's `git add` scopes. Execute serially in the order above unless each agent gets its own git worktree.

## Definition of done

- [ ] `cd libs/legal-content && node --test` — all green
- [ ] `cd apps/mobile && flutter test` — all green, count risen by the new tests only
- [ ] `cd apps/mobile && flutter analyze` — **No issues found**
- [ ] `bash scripts/check-legal-content.sh` — in sync, and proven to fail on a hand edit
- [ ] Device test green on a **real Android device** and a **real iOS device**, output pasted
- [ ] Arabic RTL checked by eye on a device
- [ ] `apps/web/privacy.html` still resolves at its original URL
- [ ] Every gap that could not be closed is named explicitly, with its platform
