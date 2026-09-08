import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DOCS, LOCALES, repoRoot } from './constants.mjs'
import { loadDocument, loadMeta } from './schema.mjs'
import { renderDart } from './render-dart.mjs'
import { renderHtml, pagePath } from './render-html.mjs'

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
  assertComplete(documents)
  return documents
}

// renderDart filters out absent documents/locales, which turns "a locale is
// missing" into a silently smaller const map: the Dart still compiles, and at
// runtime that locale falls back to English with no signal anywhere. Nothing
// downstream can see the difference — not `flutter analyze`, not the drift
// check, which compares generator output against itself. So the corpus is
// checked for completeness here, at the one point that knows what complete
// means, before it ever reaches the renderer.
export function assertComplete (documents) {
  const missing = []
  for (const doc of DOCS) {
    if (!documents[doc]) { missing.push(doc); continue }
    for (const locale of LOCALES) {
      if (!documents[doc][locale]) missing.push(`${doc}.${locale}`)
    }
  }
  if (missing.length) {
    throw new Error(
      `legal-content is incomplete — expected ${DOCS.length * LOCALES.length} ` +
      `documents (${DOCS.length} docs x ${LOCALES.length} locales), missing: ${missing.join(', ')}`,
    )
  }
  return documents
}

export function generate () {
  const meta = loadMeta()
  const documents = loadAll()
  write('apps/mobile/lib/features/legal/generated/legal_content.g.dart', renderDart(documents, meta))

  for (const doc of DOCS) {
    for (const locale of LOCALES) {
      write(`apps/web/${pagePath(doc, locale)}`,
        renderHtml(documents[doc][locale], { doc, locale, effectiveDate: meta[doc].effectiveDate }))
    }
  }
}

// Only generate when this file is executed directly. Importing it (a test
// importing `assertComplete`, say) must not rewrite a committed artifact as a
// side effect — that silently regenerated legal_content.g.dart mid-review once
// already, from content another task was still editing.
if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  generate()
}
