import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('privacy', 'en')
const allText = (d) => JSON.stringify(d).toLowerCase()
const section = (id) => JSON.stringify(doc().sections.find((s) => s.id === id)).toLowerCase()

const EXPECTED_IDS = [
  'summary', 'what-we-collect', 'where-data-lives', 'network', 'feedback',
  'purchases', 'sharing', 'retention', 'your-rights', 'children', 'changes', 'contact',
]

test('has exactly the agreed sections, in order', () => {
  assert.deepEqual(doc().sections.map((s) => s.id), EXPECTED_IDS)
})

test('says scans, OCR and storage stay on the device', () => {
  const t = section('where-data-lives')
  assert.match(t, /on your device/)
  assert.match(t, /ocr|text recognition/)
})

test('discloses that feedback creates a PUBLIC GitHub issue', () => {
  const t = section('feedback')
  assert.match(t, /public/)
  assert.match(t, /github/)
  assert.match(t, /email/)
})

test('states no scanned documents are ever sent', () => {
  assert.match(section('feedback'), /no scanned documents/)
})

test('covers in-app purchases and says Apple processes payment', () => {
  const t = section('purchases')
  assert.match(t, /apple/)
  assert.match(t, /tip/)
  assert.ok(/no payment|never receive|do not receive/.test(t), 'must say the developer receives no payment data')
})

test('scopes the no-INTERNET-permission claim to Android', () => {
  const t = section('network')
  assert.match(t, /android/)
  assert.match(t, /internet permission/)
})

test('says there is no tracking, no analytics, no ads and no sale of data', () => {
  const t = allText(doc())
  for (const w of ['no analytics', 'no ads', 'never sold', 'no tracking']) {
    assert.ok(t.includes(w), `missing claim: ${w}`)
  }
})

test('explains retention and how to delete everything', () => {
  const t = section('retention')
  assert.match(t, /uninstall/)
  assert.match(t, /delete/)
})

test('gives the support email', () => {
  assert.match(allText(doc()), /scannercamlight\.line149@passmail\.net/)
})

test('does not promise to notify users about changes to this policy', () => {
  const t = section('changes')
  assert.doesNotMatch(t, /notify|flag them|alert|inform you/)
})

test('does not promise a response time or deletion procedure it cannot keep', () => {
  const t = section('your-rights')
  assert.doesNotMatch(t, /within \d+ days|we will respond|guarantee/)
})

test('does not claim the network triggers are exhaustive', () => {
  const t = section('network')
  assert.doesNotMatch(t, /only when explicitly triggered/)
})

test('does not claim nothing is sent until Submit', () => {
  const t = section('feedback')
  assert.doesNotMatch(t, /no data is ever sent unless/)
})

test('discloses the automatic feedback-availability probe on the library screen', () => {
  const t = section('network')
  assert.match(t, /feedback (service|worker)/)
  assert.match(t, /library screen|app (opens|is opened|launches)/)
})

test('discloses Turnstile loads (and reaches Cloudflare) when the feedback form opens', () => {
  const t = section('feedback')
  assert.match(t, /turnstile/)
  assert.match(t, /cloudflare/)
  assert.match(t, /ip address/)
  // the strong claims must still hold, unweakened
  assert.match(t, /no scanned documents/)
})

test('does not gate the App Store tip-options query on a tip actually being made', () => {
  const t = section('network')
  assert.doesNotMatch(t, /when an optional in-app tip is made|only when a tip is made/)
})

test('discloses the automatic App Store product query when the support screen opens', () => {
  const t = section('network')
  assert.match(t, /app store/)
  assert.match(t, /before any tip is made/)
})
