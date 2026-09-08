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

test('allows valid bold markup', () => {
  const d = valid()
  d.sections[0].body = [{ type: 'p', text: 'This is **bold** text.' }]
  assert.doesNotThrow(() => validateDocument(d, { doc: 'terms', locale: 'en' }))
})

test('rejects unescaped ** in a paragraph', () => {
  const d = valid()
  d.sections[0].body = [{ type: 'p', text: 'This is 2 ** 3 math.' }]
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'en' }), /unescaped \*\*.*paragraph/)
})

test('rejects unescaped ** in a list item', () => {
  const d = valid()
  d.sections[0].body = [{ type: 'ul', items: ['Item with 2 ** 3 in it'] }]
  assert.throws(() => validateDocument(d, { doc: 'terms', locale: 'en' }), /unescaped \*\*.*list item/)
})

// Final review L2: the stray-`**` scan covered 2 of the 6 rendered string
// slots. `intro` is inline-rendered on BOTH surfaces (render-html.mjs
// `<p class="lead">`, legal_document_screen.dart), so a stray `**` there
// shipped as literal asterisks with a green build.
for (const field of ['title', 'intro', 'translationNotice']) {
  test(`rejects unescaped ** in ${field}`, () => {
    const doc = { ...valid(), locale: 'pt', translationNotice: 'Notice.' }
    doc[field] = 'a ** stray marker'
    assert.throws(() => validateDocument(doc, { doc: 'terms', locale: 'pt' }), /unescaped \*\*/)
  })
}

test('rejects unescaped ** in a section heading', () => {
  const doc = valid()
  doc.sections[0].heading = 'Heading ** with a stray marker'
  assert.throws(() => validateDocument(doc, { doc: 'terms', locale: 'en' }), /unescaped \*\*/)
})
