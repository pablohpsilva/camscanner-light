import { parseInline } from './inline.mjs'
import { LOCALES, webTag } from './constants.mjs'

// `esc(v)` escapes `& < > "` in that order — & first so the entities it
// introduces are not themselves re-escaped by the later replacements.
const esc = (v) => String(v)
  .replace(/&/g, '&amp;')
  .replace(/</g, '&lt;')
  .replace(/>/g, '&gt;')
  .replace(/"/g, '&quot;')

const SUPPORT_EMAIL = 'scannercamlight.line149@passmail.net'

// Fully-qualified origin for the deployed site (see .github/workflows/pages.yml
// and apps/web/README.md). hreflang specifically requires absolute URLs — a
// relative href there is not just untidy, search engines commonly ignore it,
// which would silently defeat the whole alternates block.
const SITE_ORIGIN = 'https://pablohpsilva.github.io/camscanner-light/'

// English-only category label shown above the h1. It has no translation in
// content/*.json, so it is shown only on the English page rather than leaking
// an untranslated word into a localized (and possibly RTL) document body.
const EYEBROW = { terms: 'Terms', privacy: 'Privacy', faq: 'FAQ' }

// Native-language labels for the language switcher. Chrome strings (nav,
// footer, eyebrow) stay English per the brief's "reuse verbatim" — only the
// switcher itself names each language, in that language.
const LOCALE_LABEL = {
  en: 'English',
  pt: 'Português',
  pt_BR: 'Português (Brasil)',
  es: 'Español',
  fr: 'Français',
  de: 'Deutsch',
  lb: 'Lëtzebuergesch',
  tr: 'Türkçe',
  ru: 'Русский',
  zh: '中文',
  ar: 'العربية',
}

/** `terms.html` for `en`; `legal/terms.pt-BR.html` otherwise. */
export function pagePath (doc, locale) {
  return locale === 'en' ? `${doc}.html` : `legal/${doc}.${webTag(locale)}.html`
}

// A link to a sibling document (terms.html / privacy.html / faq.html) inside
// content always resolves to the SAME locale as the page it's rendered on —
// same directory, so it never carries a `legal/` prefix, only a locale tag.
const siblingHref = (targetDoc, locale) =>
  locale === 'en' ? `${targetDoc}.html` : `${targetDoc}.${webTag(locale)}.html`

// Path from the page for (doc, fromLocale) to the page for (doc, targetLocale)
// — used by hreflang alternates and the language switcher, which must link
// across locales (unlike siblingHref, which stays within one locale).
const relativePagePath = (doc, targetLocale, fromLocale) => {
  if (fromLocale === 'en') return pagePath(doc, targetLocale)
  if (targetLocale === 'en') return `../${pagePath(doc, 'en')}`
  return siblingHref(doc, targetLocale)
}

const isSiblingDocUrl = (url) => {
  const m = /^(terms|privacy|faq)\.html$/.exec(url)
  return m ? m[1] : null
}

const renderInline = (text, { locale }) => parseInline(text).map((tok) => {
  if (tok.type === 'text') return esc(tok.text)
  if (tok.type === 'bold') return `<strong>${esc(tok.text)}</strong>`
  // link
  const siblingDoc = isSiblingDocUrl(tok.url)
  const url = siblingDoc ? siblingHref(siblingDoc, locale) : tok.url
  const external = /^https?:\/\//.test(url)
  const attrs = external ? ' target="_blank" rel="noopener noreferrer"' : ''
  return `<a href="${esc(url)}"${attrs}>${esc(tok.text)}</a>`
}).join('')

// Plain-text rendering of inline markup, for the meta description — a
// `[label](url)` keeps only its label, `**bold**` keeps only its text.
const plainText = (text) => parseInline(text).map((tok) => tok.text).join('')

// Truncate at the last word boundary within `max` chars, not mid-word —
// search-result snippets built from a truncated meta description are what a
// reader actually sees, and "…and it ha" reads as broken, not just short.
const truncate = (text, max) => {
  if (text.length <= max) return text
  const cut = text.slice(0, max)
  const lastSpace = cut.lastIndexOf(' ')
  return (lastSpace > 0 ? cut.slice(0, lastSpace) : cut) + '…'
}

const renderBody = (body, ctx) => body.map((b) => b.type === 'p'
  ? `      <p>${renderInline(b.text, ctx)}</p>`
  : `      <ul>\n${b.items.map((i) => `        <li>${renderInline(i, ctx)}</li>`).join('\n')}\n      </ul>`
).join('\n')

const renderSections = (document, ctx) => {
  if (ctx.doc === 'faq') {
    const items = document.sections.map((s) =>
      `        <details>\n          <summary>${esc(s.heading)}</summary>\n${renderBody(s.body, ctx)}\n        </details>`,
    ).join('\n')
    return `      <div class="faq">\n${items}\n      </div>`
  }
  return document.sections.map((s) =>
    `      <h2 id="${esc(s.id)}">${esc(s.heading)}</h2>\n${renderBody(s.body, ctx)}`,
  ).join('\n')
}

/** @param document One loaded, validated content JSON (schema.mjs). */
export function renderHtml (document, opts) {
  const { doc, locale, effectiveDate } = opts
  const ctx = { doc, locale }
  const prefix = locale === 'en' ? '' : '../'
  const dir = locale === 'ar' ? ' dir="rtl"' : ''

  const description = esc(truncate(plainText(document.intro), 160))

  const hreflangLinks = LOCALES
    .map((l) => `  <link rel="alternate" hreflang="${webTag(l)}" href="${SITE_ORIGIN}${pagePath(doc, l)}" />`)
    .concat(`  <link rel="alternate" hreflang="x-default" href="${SITE_ORIGIN}${pagePath(doc, 'en')}" />`)
    .join('\n')

  const langSwitch = LOCALES.map((l) => {
    const current = l === locale ? ' aria-current="page"' : ''
    return `        <a href="${relativePagePath(doc, l, locale)}"${current}>${esc(LOCALE_LABEL[l])}</a>`
  }).join('\n')

  const translationNotice = locale !== 'en' && document.translationNotice
    ? `\n      <p class="translation-notice">${esc(document.translationNotice)}</p>`
    : ''

  const eyebrow = locale === 'en'
    ? `      <span class="eyebrow">${esc(EYEBROW[doc])}</span>\n`
    : ''

  return `<!DOCTYPE html>
<html lang="${webTag(locale)}"${dir}>
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>${esc(document.title)} — ScannerCam Light</title>
  <meta name="description" content="${description}" />
  <link rel="icon" href="${prefix}assets/icon.png" />
  <link rel="stylesheet" href="${prefix}styles.css" />
${hreflangLinks}
</head>
<body>
  <header class="nav">
    <div class="container nav__inner">
      <a class="nav__brand" href="${prefix}index.html"><img src="${prefix}assets/icon.png" alt="" /> ScannerCam Light</a>
      <button class="nav__toggle" aria-label="Menu">☰</button>
      <nav class="nav__links">
        <a href="${prefix}index.html#features">Features</a>
        <a href="${prefix}index.html#privacy">Privacy</a>
        <a href="${prefix}index.html#donate">Donate</a>
        <a href="${prefix}support.html">Support</a>
        <a class="btn btn--primary" href="${prefix}index.html#get">Get the app</a>
      </nav>
    </div>
  </header>

  <main class="section">
    <div class="container prose">
${eyebrow}      <h1>${esc(document.title)}</h1>
      <p class="lead">${renderInline(document.intro, ctx)}</p>
      <p><em>${esc(document.effectiveDateLabel)}: ${esc(effectiveDate)}</em></p>${translationNotice}

${renderSections(document, ctx)}

      <nav class="lang-switch">
${langSwitch}
      </nav>
    </div>
  </main>

  <footer class="footer">
    <div class="container footer__grid">
      <div><strong>ScannerCam Light</strong><br /><span dir="ltr" style="color:#9aa4bd">Scan. Clean. Done.</span></div>
      <div>
        <a href="${siblingHref('terms', locale)}">Terms</a> &nbsp;·&nbsp;
        <a href="${siblingHref('privacy', locale)}">Privacy</a> &nbsp;·&nbsp;
        <a href="${siblingHref('faq', locale)}">FAQ</a> &nbsp;·&nbsp;
        <a href="${prefix}support.html">Support</a> &nbsp;·&nbsp;
        <a href="${prefix}index.html#donate">Donate</a> &nbsp;·&nbsp;
        <a href="mailto:${SUPPORT_EMAIL}">Contact</a>
      </div>
    </div>
  </footer>
  <script src="${prefix}main.js"></script>
</body>
</html>
`
}
