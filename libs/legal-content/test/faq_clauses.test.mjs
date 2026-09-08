import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('faq', 'en')
const section = (id) => JSON.stringify(doc().sections.find((s) => s.id === id)).toLowerCase()

const EXPECTED_IDS = [
  'offline', 'where-stored', 'is-it-free', 'tips', 'export-pdf', 'ocr-accuracy',
  'search', 'backups', 'free-space', 'feedback-public', 'languages',
  'ads-tracking', 'lost-phone', 'contact',
]

test('has exactly the agreed questions, in order', () => {
  assert.deepEqual(doc().sections.map((s) => s.id), EXPECTED_IDS)
})

test('every question reads as a question', () => {
  for (const s of doc().sections) {
    assert.ok(s.heading.includes('?'), `not a question: "${s.heading}"`)
  }
})

test('the backups answer does not contradict the terms', () => {
  const t = section('backups')
  assert.match(t, /no (cloud|backup)|not backed up/)
  assert.match(t, /your own/)
})

test('the lost-phone answer is honest about total loss', () => {
  assert.match(section('lost-phone'), /gone|lost|cannot be recovered|no way to recover/)
})

test('the feedback answer repeats the public-GitHub warning', () => {
  const t = section('feedback-public')
  assert.match(t, /public/)
  assert.match(t, /github/)
})

test('the tips answer says tips are optional and unlock nothing', () => {
  const t = section('tips')
  assert.match(t, /optional|voluntary/)
  assert.ok(/unlock|no (extra )?features|nothing/.test(t))
})

test('the ocr answer does not overclaim accuracy', () => {
  assert.match(section('ocr-accuracy'), /not (always )?perfect|imperfect|check|may/)
})

// --- Absence tests: the FAQ must not promise what the product cannot deliver ---

test('no answer promises a support response time or guaranteed help', () => {
  const full = JSON.stringify(doc()).toLowerCase()
  assert.doesNotMatch(full, /within \d+ (hours|days)|we will respond|guaranteed|will fix/)
})

test('the feedback-public answer does not claim nothing is transmitted before submit', () => {
  const t = section('feedback-public')
  assert.doesNotMatch(t, /nothing is sent until|only when you (tap|press) submit/)
})

test('the languages answer is honest that ocr and search are latin-script only', () => {
  const t = section('languages')
  assert.match(t, /ocr/)
  assert.match(t, /latin/)
  assert.match(t, /search/)
})

test('the offline answer does not gate the feedback reachability check on active use', () => {
  const t = section('offline')
  assert.doesNotMatch(t, /when actively used|only when you use/)
})

test('the offline answer does not gate StoreKit tip traffic on making a purchase', () => {
  const t = section('offline')
  assert.doesNotMatch(t, /only when actively made|only when you make/)
})

// Three independent blind back-translators (zh, ru, ar) each flagged the same
// defect in the English source: the search answer ended with a global-sounding
// "only OCR text from Latin-script documents is searchable", which reads as
// cancelling the carve-out immediately before it ("only its title will be").
// A reader could conclude titles are not searchable either — they are, via a
// separate name match that never touches the trigram index
// (document_search_service.dart `_searchRanked`: "names are not in the trigram
// index"). Presence, not absence: guards that the carve-out is stated in a form
// no trailing clause can take back.
test('the search answer states plainly that titles stay searchable', () => {
  const t = section('search')
  assert.match(t, /title (remains|stays|is still) searchable/)
})
