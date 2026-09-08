import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readdirSync, readFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { repoRoot, DOCS, LOCALES } from '../src/constants.mjs'

const webDir = resolve(repoRoot, 'apps/web')

// Every generated + hand-written page under apps/web, recursively.
function listHtml (dir) {
  const out = []
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const full = resolve(dir, entry.name)
    if (entry.isDirectory()) out.push(...listHtml(full))
    else if (entry.name.endsWith('.html')) out.push(full)
  }
  return out
}

// href AND src: an <img src> or <script src> with a wrong ../ depth 404s
// exactly like a broken <a href> — it just doesn't look like a "link".
// Dropping the prefix on <script src="../main.js"> breaks the mobile nav
// toggle on every nested page and a plain `href=`-only scan never sees it.
const HREF_OR_SRC = /(?:href|src)="([^"]*)"/g

test('every generated page exists — 33 legal pages plus the 2 hand-written ones', () => {
  const pages = listHtml(webDir)
  // 3 docs x 11 locales, plus index.html and support.html.
  assert.equal(pages.length, DOCS.length * LOCALES.length + 2)
})

test('every internal href/src resolves to a file that exists under apps/web/', () => {
  const pages = listHtml(webDir)
  assert.ok(pages.length > 0, 'expected at least one .html page under apps/web/')
  const problems = []

  for (const page of pages) {
    const html = readFileSync(page, 'utf8')
    for (const m of html.matchAll(HREF_OR_SRC)) {
      const href = m[1]
      if (href.startsWith('mailto:') || /^https?:\/\//.test(href)) continue
      // Strip a fragment; "#donate" alone means "this same page".
      const [pathPart] = href.split('#')
      if (pathPart === '') continue
      const target = resolve(dirname(page), pathPart)
      if (!existsSync(target)) {
        problems.push(`${page.replace(webDir + '/', '')}: href/src="${href}" -> missing ${target.replace(webDir + '/', '')}`)
      }
    }
  }

  assert.deepEqual(problems, [], `broken internal links:\n${problems.join('\n')}`)
})
