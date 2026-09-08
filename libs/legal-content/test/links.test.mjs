import { test } from 'node:test'
import assert from 'node:assert/strict'
import { readdirSync, readFileSync, existsSync } from 'node:fs'
import { resolve, dirname } from 'node:path'
import { repoRoot } from '../src/constants.mjs'

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

const HREF = /href="([^"]*)"/g

test('every internal href resolves to a file that exists under apps/web/', () => {
  const pages = listHtml(webDir)
  assert.ok(pages.length > 0, 'expected at least one .html page under apps/web/')
  const problems = []

  for (const page of pages) {
    const html = readFileSync(page, 'utf8')
    for (const m of html.matchAll(HREF)) {
      const href = m[1]
      if (href.startsWith('mailto:') || /^https?:\/\//.test(href)) continue
      // Strip a fragment; "#donate" alone means "this same page".
      const [pathPart] = href.split('#')
      if (pathPart === '') continue
      const target = resolve(dirname(page), pathPart)
      if (!existsSync(target)) {
        problems.push(`${page.replace(webDir + '/', '')}: href="${href}" -> missing ${target.replace(webDir + '/', '')}`)
      }
    }
  }

  assert.deepEqual(problems, [], `broken internal links:\n${problems.join('\n')}`)
})
