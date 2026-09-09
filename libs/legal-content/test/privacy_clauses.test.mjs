import { test } from 'node:test'
import assert from 'node:assert/strict'
import { loadDocument } from '../src/schema.mjs'

const doc = () => loadDocument('privacy', 'en')

// Inline bold markup (`**word**`) sits inside `**` markers that a naive regex
// scan over the raw JSON does not see through — "**nothing is sent** unless"
// contains "nothing is sent" and "unless" as separate fragments once the `**`
// interrupts them. Strip `**` before matching so absence checks see the prose
// a reader would see, not the markup, and can't be evaded by bolding a word
// mid-phrase (by hand or by a future translation).
const stripMarkup = (s) => s.replace(/\*\*/g, '')
const allText = (d) => stripMarkup(JSON.stringify(d)).toLowerCase()
const section = (id) => stripMarkup(JSON.stringify(doc().sections.find((s) => s.id === id))).toLowerCase()

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

// Document-wide, not section-scoped: the false "nothing happens before Submit"
// claim previously reappeared in `your-rights`, two sections away from `feedback`,
// as a paraphrase a single literal string could not catch. Checking the whole
// document, against a family of phrasings, is the point of this guard.
//
// This family covers only UNIVERSAL claims ("nothing"/"no data" is ever sent) —
// denials that the probe and Turnstile exist. It deliberately does NOT include
// a bare "only when you tap submit": that phrasing is also used, correctly, to
// scope a true, SUBJECT-specific claim ("your message ... is sent only when you
// tap Submit") — a guard that can't tell those apart just pressures whoever
// hits it into deleting accurate text. The subject-specific claim is guarded
// by a presence test below instead, which can't be satisfied by deletion.
test('does not claim nothing is sent until Submit, anywhere in the document', () => {
  const t = allText(doc())
  assert.doesNotMatch(
    t,
    /nothing is sent unless|no data is ever sent unless|not until you submit|no request .{0,30} before you submit/,
  )
})

// Presence, not absence: guards the FACT that message/email/diagnostics are
// Submit-gated. An absence test on "only when you tap submit" could be
// satisfied by deleting the word "only" — which is exactly what happened once
// before. A presence test can't be satisfied that way.
test('states the message/email/diagnostics fields are sent only on Submit', () => {
  const t = section('feedback')
  assert.match(t, /sent only when you tap submit/)
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

test('does not gate the App Store tip-options query on a tip actually being made, anywhere in the document', () => {
  const t = allText(doc())
  assert.doesNotMatch(t, /when an optional in-app tip is made|only when a tip is made/)
})

test('discloses the automatic App Store product query when the support screen opens', () => {
  const t = section('network')
  assert.match(t, /app store/)
  assert.match(t, /before any tip is made/)
})

// Proves the bold-stripping fix actually closes the evasion hole, not just that
// the code changed. A gating claim with `**` split across the middle of the
// phrase used to slip straight through a raw-text regex scan.
test('bold markup cannot be used to evade a gating-claim absence check', () => {
  const bolded = JSON.stringify({ text: '**Nothing is sent** unless the form is opened.' })
  const GATING_CLAIM = /nothing is sent unless/

  // Before stripping: the raw JSON does NOT match, because "**" splits the
  // phrase — this is the hole the team lead found.
  assert.doesNotMatch(bolded.toLowerCase(), GATING_CLAIM)

  // After stripping (what allText()/section() now do): the same claim IS
  // caught.
  assert.match(stripMarkup(bolded).toLowerCase(), GATING_CLAIM)
})

// --- Sweep guard for the recurring defect class -----------------------------
//
// H1-H5 and M1 of the cross-document review were not six bugs but one: an
// ABSOLUTE ("everything", "nothing", "the sole exception") or USER-TRIGGERED
// ("actively chosen", "explicitly user-initiated", "features you choose to
// use") framing of network activity that is in fact AUTOMATIC. The app has
// three automatic outbound paths — the feedback-availability probe on library
// open, the Cloudflare Turnstile challenge on feedback-form open, and the App
// Store tip-options query on support-screen open — none of which the user
// triggers.
//
// That defect had been found and fixed SEVEN times before this guard existed,
// section by section, and each time it reappeared in a different section or a
// different document. So this list is checked DOCUMENT-WIDE, and the identical
// list is checked in faq_clauses and terms_clauses too: a phrase deleted from
// the Privacy Policy must not be able to reappear in the Terms or the FAQ.
//
// Every entry is a UNIVERSAL denial or a user-gating of automatic traffic, so
// none of them can be true given the three automatic paths. Narrower, true
// "only" claims (e.g. "your message ... is sent only when you tap Submit") are
// deliberately NOT in this list, and are guarded by presence tests instead.
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

// Presence pair for the sweep guard: deleting the offending clause must not be
// enough — the Summary is the most-read section, so it has to carry the fact.
test('the Summary discloses that some network activity is automatic', () => {
  const t = section('summary')
  assert.match(t, /automatic/)
  assert.match(t, /library screen|feedback service/)
})

test('the what-is-collected carve-out is not limited to the feedback feature', () => {
  const t = section('what-we-collect')
  assert.match(t, /app store|tip options/)
})

test('the network section admits the automatic requests on iOS instead of denying them', () => {
  const t = section('network')
  assert.match(t, /ios/)
  assert.match(t, /automatic/)
  assert.match(t, /turnstile|cloudflare/)
})

test('states what the missing Android INTERNET permission means for the feedback feature', () => {
  const t = section('network')
  assert.match(t, /android/)
  assert.match(t, /not offered|cannot reach|is not available/)
})

test('the feedback section scopes availability to builds that can reach the network', () => {
  const t = section('feedback')
  assert.match(t, /android/)
})

test("the children's section does not rest on feedback being user-initiated", () => {
  const t = section('children')
  assert.match(t, /automatic/)
  assert.match(t, /turnstile|cloudflare|feedback service|library screen/)
})

test('hedges tip and donation availability the way every other document does', () => {
  const t = section('purchases')
  assert.match(t, /depending on (your )?platform and app version/)
  assert.match(t, /where a donation option is offered/)
})

test('does not overstate on-device deletion as a storage-level erasure', () => {
  const t = section('retention')
  assert.doesNotMatch(t, /complete and immediate/)
  assert.match(t, /operating system|overwritten/)
})

test('qualifies the public-GitHub-issue removal commitment', () => {
  const t = section('your-rights')
  assert.match(t, /cached|copied, |indexed/)
})

test('cross-references the purchases section by the heading it actually has', () => {
  const t = section('network')
  assert.match(t, /in-app purchases and tips section/)
  assert.doesNotMatch(t, /the purchases section/)
})

// --- the tenth instance of the gating-claim class (final review, H1) --------
// `children` enumerated two automatic requests and then closed the scope: "is
// the whole of what happens without a deliberate action". There are THREE — the
// App Store tip-options query fires on the iOS support screen opening — and this
// same file enumerates all three twice, 55 lines away. A direct self-
// contradiction in the most legally sensitive section of the document whose URL
// is registered with Apple and Google.
//
// None of the 181 tests could see it: the absence guards target the PHRASINGS of
// universal claims ("nothing is sent unless..."), and this used a scope-CLOSING
// construction instead. Blind back-translation could not see it either — the
// translations rendered the wrong English faithfully.
//
// Presence, not absence, for the fact itself (R26: an absence test here would
// pressure deleting true content). The absence guard is scoped to the narrow
// family of exhaustiveness closers, which have no legitimate use in a section
// that enumerates a subset.
test('the children section names all three automatic requests, not two', () => {
  const t = section('children')
  assert.match(t, /feedback service|reachable/)
  assert.match(t, /cloudflare|turnstile/)
  assert.match(t, /app store/, 'the App Store tip-options query is the one that keeps being dropped')
})

test('no section closes the scope of the automatic requests it enumerates', () => {
  const t = allText(doc())
  assert.doesNotMatch(
    t,
    /is the whole of what happens|is all that happens without|are the only things that happen without|nothing else happens without/,
  )
})

// --- mandatory-rights backstop (final review, M5) --------------------------
// your-rights honestly says no removal timeframe is promised. For feedback data
// the developer IS a controller (they run the Worker and the repository), and
// GDPR Art. 12(3) sets a one-month deadline — so that sentence read as
// disclaiming a statutory duty. The Terms carry a mandatory-rights carve-out;
// the Privacy Policy did not, and it is the document that discusses GDPR.
test('the privacy policy carries its own mandatory-rights saving clause', () => {
  const t = section('your-rights')
  assert.match(t, /law that applies to you|applicable law/)
  assert.match(t, /regardless of anything above|cannot be excluded|applies regardless/)
})

// --- third-party identity guarantee (user request) -------------------------
// The app holds no identity, so it has none to pass on. Stated positively so
// it cannot be satisfied by deleting text, and paired with the specific
// disclosures so the strong claim never drifts into an unqualified absolute.
test('the sharing section states the app holds no identity to hand out', () => {
  const t = section('sharing')
  assert.match(t, /never handed to anyone|does not hold one/)
  assert.match(t, /no accounts|no sign-in/)
  assert.match(t, /advertising identifier/)
  assert.match(t, /never sold|never .{0,20}sold/)
})

test('the sharing section still names what each third party does receive', () => {
  const t = section('sharing')
  assert.match(t, /cloudflare/)
  assert.match(t, /ip address/)
  assert.match(t, /github/)
  assert.match(t, /apple/)
  // the strong claim must not swallow the honest carve-outs
  assert.match(t, /only if you chose|only because you chose|if you chose/)
})
