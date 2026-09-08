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
