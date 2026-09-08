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

// --- Fix round 1 (review findings H1/H3/M4/M5): regression + new-behaviour tests ---

const ar = { ...doc, locale: 'ar' }
const faqDoc = {
  doc: 'faq', locale: 'en', title: 'FAQ', effectiveDateLabel: 'Effective date',
  translationNotice: '', intro: 'FAQ intro',
  sections: [
    { id: 'q1', heading: 'Does it work offline?', body: [{ type: 'p', text: 'Yes.' }] },
    { id: 'q2', heading: 'Is it free?', body: [{ type: 'p', text: 'Yes.' }] },
  ],
}

test('sets dir="rtl" on Arabic pages and omits it everywhere else', () => {
  assert.ok(renderHtml(ar, opts('ar')).includes('<html lang="ar" dir="rtl">'))
  assert.ok(!renderHtml(doc, opts('en')).includes('dir="rtl"'))
  assert.ok(!renderHtml(de, opts('de')).includes('dir="rtl"'))
})

test('hyphenates an underscore locale tag in lang (regression: found lang="pt_BR" by hand)', () => {
  const ptBr = { ...doc, locale: 'pt_BR' }
  assert.ok(renderHtml(ptBr, opts('pt_BR')).includes('<html lang="pt-BR">'))
})

test('renders a FAQ document as a details/summary accordion, not plain headings', () => {
  const out = renderHtml(faqDoc, { doc: 'faq', locale: 'en', effectiveDate: '2026-09-08' })
  assert.ok(out.includes('<div class="faq">'))
  assert.ok(out.includes('<details>'))
  assert.ok(out.includes('<summary>Does it work offline?</summary>'))
})

test('escapes a hostile link URL used as an href', () => {
  const hostile = {
    ...doc,
    sections: [{ id: 'a', heading: 'A', body: [
      { type: 'p', text: 'Go [here](https://e.com/x?a=1&b="2)' },
    ] }],
  }
  const out = renderHtml(hostile, opts('en'))
  assert.ok(out.includes('href="https://e.com/x?a=1&amp;b=&quot;2"'))
})

test('adds target="_blank" on external links and omits it on mailto links', () => {
  const withLinks = {
    ...doc,
    sections: [{ id: 'a', heading: 'A', body: [
      { type: 'p', text: 'Visit [our site](https://example.com) or [email us](mailto:test@example.com).' },
    ] }],
  }
  const out = renderHtml(withLinks, opts('en'))
  assert.ok(out.includes('<a href="https://example.com" target="_blank" rel="noopener noreferrer">our site</a>'))
  assert.ok(out.includes('<a href="mailto:test@example.com">email us</a>'))
  assert.ok(!/href="mailto:test@example\.com"[^>]*target="_blank"/.test(out))
})

test('drops aria-current from every switcher entry except the current locale', () => {
  const out = renderHtml(de, opts('de'))
  assert.equal((out.match(/aria-current="page"/g) || []).length, 1)
  assert.match(out, /<a href="[^"]*"[^>]*>Deutsch<\/a>/)
  assert.ok(out.includes('aria-current="page">Deutsch</a>'))
})

test('nested pages reach main.js and the icon with ../, not just styles.css', () => {
  const out = renderHtml(de, opts('de'))
  assert.ok(out.includes('src="../main.js"'))
  assert.ok(out.includes('src="../assets/icon.png"'))
})

test('omits the hard-coded English eyebrow label on non-English pages', () => {
  assert.ok(renderHtml(doc, opts('en')).includes('<span class="eyebrow">'))
  assert.ok(!renderHtml(de, opts('de')).includes('<span class="eyebrow">'))
  assert.ok(!renderHtml(ar, opts('ar')).includes('<span class="eyebrow">'))
})

test('hreflang alternates are fully-qualified so crawlers honour them', () => {
  const out = renderHtml(doc, opts('en'))
  assert.ok(out.includes('hreflang="en" href="https://pablohpsilva.github.io/camscanner-light/terms.html"'))
  assert.ok(out.includes('hreflang="pt-BR" href="https://pablohpsilva.github.io/camscanner-light/legal/terms.pt-BR.html"'))
  assert.ok(out.includes('hreflang="x-default" href="https://pablohpsilva.github.io/camscanner-light/terms.html"'))
  // Also correct from a nested page, where the plain relative path would differ.
  const nested = renderHtml(de, opts('de'))
  assert.ok(nested.includes('hreflang="de" href="https://pablohpsilva.github.io/camscanner-light/legal/terms.de.html"'))
})

test('wraps the English footer tagline in dir="ltr" so it does not reorder under RTL', () => {
  assert.ok(renderHtml(ar, opts('ar')).includes('<span dir="ltr" style="color:#9aa4bd">Scan. Clean. Done.</span>'))
})

test('carries a non-empty meta description built from the intro', () => {
  const out = renderHtml(doc, opts('en'))
  assert.match(out, /<meta name="description" content="[^"]+" \/>/)
})

test('the favicon link, not just the nav-brand image, carries the ../ prefix on nested pages', () => {
  const out = renderHtml(de, opts('de'))
  assert.ok(out.includes('<link rel="icon" href="../assets/icon.png" />'))
})

test('a long meta description truncates on a word boundary with an ellipsis, not mid-word', () => {
  const longIntro = 'Alpha bravo charlie delta echo foxtrot golf hotel india juliet kilo lima mike '
    + 'november oscar papa quebec romeo sierra tango uniform victor whiskey yankee zulu end.'
  const longDoc = { ...doc, intro: longIntro }
  const out = renderHtml(longDoc, opts('en'))
  const m = /<meta name="description" content="([^"]*)" \/>/.exec(out)
  assert.ok(m, 'expected a meta description tag')
  const desc = m[1]
  assert.ok(desc.endsWith('…'), `expected an ellipsis, got: ${JSON.stringify(desc)}`)
  const withoutEllipsis = desc.slice(0, -1)
  assert.ok(longIntro.startsWith(withoutEllipsis), 'truncation must not cut mid-word')
  assert.ok(withoutEllipsis.length <= 160)
})
