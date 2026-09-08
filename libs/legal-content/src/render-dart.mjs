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
// Regenerate (both, from the repo root):
//   node libs/legal-content/src/generate.mjs
//   node libs/legal-content/src/inline-parity-fixture.mjs
// ignore_for_file: type=lint, type=warning
// dart format off

import '../legal_models.dart';

/// Every legal document, keyed by LegalDoc.key then by locale tag ('pt_BR').
const Map<String, Map<String, LegalDocument>> kLegalContent = {
${body}
};
`
}
