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
