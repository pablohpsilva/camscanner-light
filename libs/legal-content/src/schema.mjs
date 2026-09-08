import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { contentDir } from './constants.mjs'
import { parseInline } from './inline.mjs'

const isNonEmpty = (v) => typeof v === 'string' && v.trim().length > 0

/** Throws with a precise, file-identifying message if `json` is not a valid document. */
/// Rejects a stray `**` anywhere a string is rendered through the inline
/// parser. Checking only `p.text` and `ul` items covered 2 of the 6 rendered
/// slots — `intro` is inline-rendered on both the website and the app screen,
/// so a stray `**` there shipped as literal asterisks with a green build.
/// Checking only `text` tokens also made markup inside a link label invisible.
function assertNoStrayBold (value, where, what) {
  if (typeof value !== 'string' || value === '') return
  for (const token of parseInline(value)) {
    if (token.text.includes('**')) {
      throw new Error(`${where}: unescaped ** in ${what}`)
    }
  }
}

export function validateDocument (json, { doc, locale }) {
  const where = `${doc}.${locale}.json`
  if (json.doc !== doc) throw new Error(`${where}: doc "${json.doc}" — expected "${doc}"`)
  if (json.locale !== locale) throw new Error(`${where}: locale "${json.locale}" — expected "${locale}"`)
  for (const field of ['title', 'effectiveDateLabel', 'intro']) {
    if (!isNonEmpty(json[field])) throw new Error(`${where}: ${field} must be a non-empty string`)
  }
  assertNoStrayBold(json.title, where, 'title')
  assertNoStrayBold(json.intro, where, 'intro')
  assertNoStrayBold(json.translationNotice, where, 'translationNotice')
  if (locale !== 'en' && !isNonEmpty(json.translationNotice)) {
    throw new Error(`${where}: translationNotice is required on non-English documents`)
  }
  if (!Array.isArray(json.sections) || json.sections.length === 0) {
    throw new Error(`${where}: sections must be a non-empty array`)
  }
  const seen = new Set()
  for (const s of json.sections) {
    if (!isNonEmpty(s.id)) throw new Error(`${where}: every section needs a non-empty id`)
    if (seen.has(s.id)) throw new Error(`${where}: duplicate section id "${s.id}"`)
    seen.add(s.id)
    if (!isNonEmpty(s.heading)) throw new Error(`${where}: section "${s.id}" has an empty heading`)
    assertNoStrayBold(s.heading, where, `section "${s.id}" heading`)
    if (!Array.isArray(s.body) || s.body.length === 0) {
      throw new Error(`${where}: section "${s.id}" has an empty body`)
    }
    for (const b of s.body) {
      if (b.type === 'p') {
        if (!isNonEmpty(b.text)) throw new Error(`${where}: section "${s.id}" has an empty p block`)
        assertNoStrayBold(b.text, where, `section "${s.id}" paragraph`)
      } else if (b.type === 'ul') {
        if (!Array.isArray(b.items) || b.items.length === 0 || !b.items.every(isNonEmpty)) {
          throw new Error(`${where}: section "${s.id}" has a ul block with empty items`)
        }
        for (const item of b.items) {
          assertNoStrayBold(item, where, `section "${s.id}" list item`)
        }
      } else {
        throw new Error(`${where}: section "${s.id}" has unknown block type "${b.type}"`)
      }
    }
  }
}

export function loadMeta () {
  return JSON.parse(readFileSync(resolve(contentDir, 'meta.json'), 'utf8'))
}

/** Reads, parses, and validates one content file. */
export function loadDocument (doc, locale) {
  const json = JSON.parse(readFileSync(resolve(contentDir, `${doc}.${locale}.json`), 'utf8'))
  validateDocument(json, { doc, locale })
  return json
}
