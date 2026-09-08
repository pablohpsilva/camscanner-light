// Writes the JS-side tokenisation of every string in every content file, so a
// Dart test can assert parseLegalInline() produces the same tokens.
//
// The app and the website render the SAME content strings through two separate
// inline parsers. Mirrored unit fixtures prove the two agree on the cases
// someone thought to write down; this proves they agree on the corpus that
// actually ships — 1400+ strings across 11 languages, including every real
// bold span, link, stray asterisk and RTL string in the documents.
import { writeFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { fileURLToPath } from 'node:url'
import { DOCS, LOCALES, repoRoot } from './constants.mjs'
import { loadDocument } from './schema.mjs'
import { parseInline } from './inline.mjs'

export const FIXTURE_PATH =
  'apps/mobile/test/features/legal/inline_parity_fixture.json'

export function buildInlineParityFixture () {
  const seen = new Set()
  const cases = []
  const add = (s) => {
    if (typeof s !== 'string' || seen.has(s)) return
    seen.add(s)
    cases.push({ input: s, tokens: parseInline(s) })
  }
  for (const doc of DOCS) {
    for (const locale of LOCALES) {
      const d = loadDocument(doc, locale)
      add(d.intro); add(d.title); add(d.translationNotice)
      for (const s of d.sections) {
        add(s.heading)
        for (const b of s.body) {
          if (b.type === 'p') add(b.text)
          else b.items.forEach(add)
        }
      }
    }
  }
  return cases
}

export function writeInlineParityFixture () {
  const cases = buildInlineParityFixture()
  writeFileSync(resolve(repoRoot, FIXTURE_PATH), JSON.stringify(cases, null, 1) + '\n')
  return cases.length
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  console.log(`wrote ${FIXTURE_PATH} (${writeInlineParityFixture()} strings)`)
}
