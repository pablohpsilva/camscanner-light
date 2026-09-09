import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('faq', 'en')
// Strip `**` before matching, exactly as privacy_clauses does: a guard that
// scans raw JSON can be evaded by bolding a word mid-phrase.
const stripMarkup = (s) => s.replace(/\*\*/g, '')
const allText = (d) => stripMarkup(JSON.stringify(d)).toLowerCase()
const section = (id) => stripMarkup(JSON.stringify(doc().sections.find((s) => s.id === id))).toLowerCase()

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

// --- Sweep guard for the recurring defect class -----------------------------
//
// The same list guards privacy_clauses, faq_clauses and terms_clauses. The
// defect — an ABSOLUTE or USER-TRIGGERED framing of network activity that is in
// fact AUTOMATIC (the feedback-availability probe on library open, the
// Cloudflare Turnstile challenge on feedback-form open, the App Store
// tip-options query on support-screen open) — was fixed SEVEN times section by
// section before this guard existed, and each time it reappeared somewhere
// else. Checking every document against the identical list is what stops a
// phrase deleted here from being reintroduced there.
//
// Every entry is a UNIVERSAL denial or a user-gating of automatic traffic, so
// none can be true. Narrower, TRUE "only" claims are deliberately absent from
// this list and are guarded by presence tests instead.
const FALSE_ABSOLUTES = [
  /everything stays on the device/,
  /only transmits data when/,
  /when it is actively chosen/,
  /one explicit exception/,
  /the sole exception/,
  /the only exception/,
  /unrelated to a feature you are actively using/,
  /makes no background (network )?requests/,
  /performs no background data collection/,
  /explicitly user-initiated/,
  /no passive data-collection risk/,
  /nothing about app usage/,
  /features you choose to use/,
  /nothing is uploaded anywhere/,
  /because the app is offline and free/,
]

test('carries none of the known false absolutes about network activity', () => {
  const t = allText(doc())
  for (const re of FALSE_ABSOLUTES) assert.doesNotMatch(t, re, `false absolute present: ${re}`)
})

test('the ads-and-tracking answer does not deny the automatic feedback requests', () => {
  const t = section('ads-tracking')
  assert.match(t, /automatic/)
  assert.match(t, /cloudflare|feedback service|library screen/)
})

test('the feedback answer scopes availability away from released Android', () => {
  const t = section('feedback-public')
  assert.match(t, /android/)
})

// Presence, not absence: the no-upload claim must survive, bound to the subject
// it is true of (documents), rather than being deleted or left global.
test('the where-stored answer binds its no-upload claim to the documents', () => {
  const t = section('where-stored')
  assert.match(t, /none of it is uploaded/)
})

// --- donation data-handling (user request) ---------------------------------
test('the tips answer says the app passes on nothing about the user', () => {
  const t = section('tips')
  assert.match(t, /passes on nothing about you|nothing about you/)
  assert.match(t, /no payment details|receives no payment/)
})

// Bitcoin is pseudonymous, not anonymous. Saying otherwise in a privacy
// document would mislead someone into relying on anonymity they do not have.
// The true, narrower claim is that the APP makes no request.
test('the tips answer is honest that the Bitcoin ledger is public', () => {
  const t = section('tips')
  assert.match(t, /public ledger/)
  assert.match(t, /traceable|traced/)
})
