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

// --- completeness (review finding M1) -------------------------------------
// renderDart silently drops absent documents/locales, so an incomplete corpus
// produces a smaller const map that still compiles and still passes every
// other check — the locale just falls back to English at runtime with no
// signal. Mutation-testing showed dropping 'ar' passed the whole suite.
import { assertComplete } from '../src/generate.mjs'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { DOCS, LOCALES, repoRoot } from '../src/constants.mjs'

const fullCorpus = () => {
  const d = {}
  for (const doc of DOCS) {
    d[doc] = {}
    for (const l of LOCALES) d[doc][l] = { sections: [] }
  }
  return d
}

test('assertComplete accepts a full corpus', () => {
  assert.doesNotThrow(() => assertComplete(fullCorpus()))
})

test('assertComplete rejects a missing locale and names it', () => {
  const corpus = fullCorpus()
  delete corpus.faq.ar
  assert.throws(() => assertComplete(corpus), /faq\.ar/)
})

test('assertComplete rejects a missing document and names it', () => {
  const corpus = fullCorpus()
  delete corpus.privacy
  assert.throws(() => assertComplete(corpus), /privacy/)
})

test('the committed Dart artifact holds all 33 documents', () => {
  const artifact = readFileSync(
    resolve(repoRoot, 'apps/mobile/lib/features/legal/generated/legal_content.g.dart'),
    'utf8',
  )
  const entries = artifact.match(/': LegalDocument\(/g) ?? []
  assert.equal(entries.length, DOCS.length * LOCALES.length)
  for (const l of LOCALES) {
    assert.ok(artifact.includes(`'${l}': LegalDocument(`), `artifact is missing locale ${l}`)
  }
})

// --- field fidelity (review finding M2) -----------------------------------
// Mutation-testing showed that rendering `heading` from `sec.id` compiles and
// ships wrong text while passing every existing test. These pin the actual
// field values, not just the shape.
test('renders section id and heading as distinct fields, in order', () => {
  const out = renderDart(docs, meta)
  assert.match(out, /LegalSection\('a', 'A', \[/)
})

test('round-trips a backslash and a newline without breaking the literal', () => {
  const tricky = {
    terms: {
      en: {
        doc: 'terms', locale: 'en', title: 'T', effectiveDateLabel: 'E',
        translationNotice: '', intro: 'I',
        sections: [{ id: 'x', heading: 'H', body: [{ type: 'p', text: 'a\\b\nc' }] }],
      },
    },
  }
  const out = renderDart(tricky, meta)
  assert.match(out, /'a\\\\b\\nc'/)
  assert.ok(!/'a\\b$/m.test(out), 'a raw newline must not break the Dart literal')
})
