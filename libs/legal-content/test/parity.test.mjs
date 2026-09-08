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
  // as a "translation". A whole-document concatenation isn't enough either: with
  // 14-41 sections per document, a batch translation that copies a handful of
  // sections verbatim would still produce a concatenation that differs from
  // English overall, and would sail through undetected. Compare PER SECTION
  // instead, so a partially-copied translation fails and names the untranslated
  // section id(s), one test per (doc, locale) so a failure points at exactly the
  // file responsible.
  for (const locale of LOCALES.filter((l) => l !== 'en')) {
    test(`${doc}: ${locale} is not just copied English, section by section`, () => {
      const en = loadDocument(doc, 'en')
      const other = loadDocument(doc, locale)
      assert.notEqual(other.title, en.title, `${doc}.${locale}.json title is still English`)
      assert.notEqual(other.effectiveDateLabel, en.effectiveDateLabel,
        `${doc}.${locale}.json effectiveDateLabel is still English`)
      const sectionText = (s) =>
        s.body.map((b) => (b.type === 'p' ? b.text : b.items.join(' '))).join(' ')
      const copiedIds = en.sections
        .filter((enSection, i) => sectionText(enSection) === sectionText(other.sections[i]))
        .map((s) => s.id)
      assert.deepEqual(copiedIds, [],
        `${doc}.${locale}.json has section(s) copied verbatim from English: ${copiedIds.join(', ')}`)
    })
  }

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
