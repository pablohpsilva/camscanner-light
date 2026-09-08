import { mkdirSync, writeFileSync } from 'node:fs'
import { dirname, resolve } from 'node:path'
import { DOCS, LOCALES, repoRoot } from './constants.mjs'
import { loadDocument, loadMeta } from './schema.mjs'
import { renderDart } from './render-dart.mjs'

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
  return documents
}

export function generate () {
  const meta = loadMeta()
  const documents = loadAll()
  write('apps/mobile/lib/features/legal/generated/legal_content.g.dart', renderDart(documents, meta))
}

generate()
