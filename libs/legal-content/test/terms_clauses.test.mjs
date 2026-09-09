import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('terms', 'en')
// Strip `**` before matching, exactly as privacy_clauses does: a guard that
// scans raw JSON can be evaded by bolding a word mid-phrase.
const stripMarkup = (s) => s.replace(/\*\*/g, '')
const allText = (d) => stripMarkup(JSON.stringify(d)).toLowerCase()
const section = (id) => stripMarkup(JSON.stringify(doc().sections.find((s) => s.id === id))).toLowerCase()

const EXPECTED_IDS = [
  'acceptance', 'licence', 'your-content', 'no-warranty', 'limitation-of-liability',
  'data-loss', 'accuracy', 'third-parties', 'donations', 'acceptable-use',
  'indemnity', 'termination', 'changes', 'your-rights', 'contact',
]

test('has exactly the agreed sections, in order', () => {
  assert.deepEqual(doc().sections.map((s) => s.id), EXPECTED_IDS)
})

test('states that use constitutes acceptance', () => {
  const s = doc().sections.find((x) => x.id === 'acceptance')
  assert.match(JSON.stringify(s).toLowerCase(), /by using/)
})

test('disclaims warranty in the conventional terms', () => {
  const t = allText(doc())
  for (const phrase of ['as is', 'without warranty', 'merchantability', 'fitness for a particular purpose', 'non-infringement']) {
    assert.ok(t.includes(phrase), `missing warranty phrase: ${phrase}`)
  }
})

test('limits liability and names the cap', () => {
  const s = doc().sections.find((x) => x.id === 'limitation-of-liability')
  const t = JSON.stringify(s).toLowerCase()
  assert.match(t, /amount you (have )?actually paid/)
  assert.match(t, /indirect|consequential/)
})

test('places responsibility for scanned content on the user', () => {
  const s = doc().sections.find((x) => x.id === 'your-content')
  const t = JSON.stringify(s).toLowerCase()
  assert.match(t, /solely responsible/)
  assert.match(t, /right to (scan|copy)/)
})

test('warns about data loss and tells the user to keep backups', () => {
  const s = doc().sections.find((x) => x.id === 'data-loss')
  const t = JSON.stringify(s).toLowerCase()
  assert.match(t, /no backup|not backed up/)
  assert.match(t, /own (copies|backups)/)
})

test('says OCR output must not be relied on for legal, medical or financial purposes', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'accuracy')).toLowerCase()
  for (const w of ['legal', 'medical', 'financial']) assert.ok(t.includes(w), `missing: ${w}`)
})

test('says donations and tips are non-refundable and buy nothing', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'donations')).toLowerCase()
  assert.match(t, /non-refundable/)
  assert.match(t, /voluntary/)
})

test('preserves mandatory local consumer rights', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'your-rights')).toLowerCase()
  assert.match(t, /cannot be (excluded|limited)|mandatory/)
})

test('names no governing law or court', () => {
  const t = allText(doc())
  for (const w of ['governing law', 'jurisdiction of the courts', 'exclusive jurisdiction', 'venue']) {
    assert.ok(!t.includes(w), `must not contain a governing-law clause: ${w}`)
  }
})

test('names no individual person as publisher', () => {
  assert.ok(allText(doc()).includes('the developer of scannercam light'))
})

test('gives the support email', () => {
  assert.match(allText(doc()), /scannercamlight\.line149@passmail\.net/)
})

test('does not promise to notify users about changes to these terms', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'changes')).toLowerCase()
  assert.doesNotMatch(t, /notify|flag them|alert|inform you/)
})

test('does not claim the in-app copy is always current', () => {
  const t = JSON.stringify(doc().sections.find((x) => x.id === 'changes')).toLowerCase()
  assert.doesNotMatch(t, /current version is always|always available within the app/)
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

test('the intro does not present the app as unqualifiedly offline', () => {
  const t = stripMarkup(doc().intro).toLowerCase()
  assert.doesNotMatch(t, /free, offline, on-device/)
  assert.match(t, /automatic/)
})

test('the third-party list names Cloudflare', () => {
  assert.match(section('third-parties'), /cloudflare/)
})

test('the third-party framing separates automatic contact from chosen contact', () => {
  assert.match(section('third-parties'), /automatic/)
})

// L1: the FAQ sends readers here for the "full" accuracy disclaimer, so the
// hardest OCR limitation — whole scripts are not read at all — has to be here.
test('the accuracy section carries the Latin-script OCR limitation', () => {
  const t = section('accuracy')
  assert.match(t, /latin/)
  assert.match(t, /chinese|arabic|cyrillic/)
})

test('the termination clause does not justify itself with the app being offline', () => {
  assert.doesNotMatch(section('termination'), /because the app is offline/)
})

// --- third-party data-handling guarantee ------------------------------------
test('the third-party section opens by stating no data is handed out', () => {
  const t = section('third-parties')
  assert.match(t, /does not hand out your data/)
  assert.match(t, /no user accounts|there are no user accounts/)
  assert.match(t, /sold, rented|never sold/)
})

test('the third-party section says what each party can actually learn', () => {
  const t = section('third-parties')
  assert.match(t, /ip address/)          // Cloudflare
  assert.match(t, /only if you chose to enter one|only because you chose/) // GitHub email
  assert.match(t, /aggregate/)           // Apple sales reporting
  assert.match(t, /tells ko-fi nothing|nothing about you/) // Ko-fi
})

// Bitcoin is pseudonymous, not anonymous: every transaction sits on a permanent
// public ledger and chain analysis is routine. A privacy document that implied
// otherwise would be both false and actively harmful — someone could rely on it
// for anonymity they do not have. The true claim is narrower: the APP transmits
// nothing when a Bitcoin address is shown.
test('no document claims Bitcoin donations are untraceable or anonymous', () => {
  for (const d of ['terms', 'privacy', 'faq']) {
    const t = JSON.stringify(loadDocument(d, 'en')).toLowerCase()
    assert.doesNotMatch(
      t,
      /bitcoin[^.]{0,120}(untraceable|anonymous|nobody (can )?track|cannot be traced|no one tracks)/,
      `${d} must not present Bitcoin as untraceable`,
    )
  }
})

test('the Bitcoin option is honest that the ledger is public', () => {
  const t = section('third-parties')
  assert.match(t, /public ledger/)
  assert.match(t, /traced|traceable/)
})
