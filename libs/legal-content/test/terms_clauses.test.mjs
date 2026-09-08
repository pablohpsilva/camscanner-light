import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('terms', 'en')
const allText = (d) => JSON.stringify(d).toLowerCase()

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
