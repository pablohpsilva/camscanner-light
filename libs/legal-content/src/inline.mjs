// The ONLY inline markup allowed in legal content: **bold** and [label](url).
// Deliberately tiny — the Dart renderer must reimplement it exactly
// (apps/mobile/lib/features/legal/legal_inline.dart), so every addition here
// is a change in two languages plus two test suites.
const PATTERN = /\*\*(.+?)\*\*|\[([^\]]+)\]\(([^)\s]+)\)/g

/** @returns {Array<{type:'text'|'bold'|'link', text: string, url?: string}>} */
export function parseInline (text) {
  const tokens = []
  let last = 0
  for (const m of text.matchAll(PATTERN)) {
    if (m.index > last) tokens.push({ type: 'text', text: text.slice(last, m.index) })
    if (m[1] !== undefined) tokens.push({ type: 'bold', text: m[1] })
    else tokens.push({ type: 'link', text: m[2], url: m[3] })
    last = m.index + m[0].length
  }
  if (last < text.length) tokens.push({ type: 'text', text: text.slice(last) })
  return tokens
}
