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
