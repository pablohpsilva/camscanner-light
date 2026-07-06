# ScannerCam Light Marketing Site Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a static, 3-page GitHub Pages site (marketing landing + support + privacy) for ScannerCam Light, using real screenshots captured from the device.

**Architecture:** Plain static HTML/CSS/vanilla-JS in a new `apps/web/` folder, isolated from the Flutter app. No framework, no Node build. A shared `styles.css` design system drives all pages; `main.js` adds a nav toggle, smooth scroll, and a screenshot lightbox. Real screenshots are captured from Android device `RZCY51D0T1K` and framed in CSS device mockups.

**Tech Stack:** HTML5, CSS3 (custom properties, fl/grid), vanilla JS. `adb` for screenshot capture. Playwright (existing MCP) for verification.

## Global Constraints

- Everything lives under `apps/web/`; **do not modify** `apps/mobile/` or any Flutter code.
- No external network requests at runtime (no CDN fonts/scripts/analytics). Site must work fully offline.
- Colors (verbatim): `--accent:#2E7DFF`, `--ink:#1A2238`, `--bg:#FFFFFF`, `--surface:#F5F8FC`, `--muted:#5B6478`.
- Font: system stack `-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif`.
- Support email (verbatim): `scannercamlight.line149@passmail.net`.
- Store buttons say **"Coming soon"** — no live store URLs.
- Privacy claims must stay within verified facts: no `INTERNET` permission, no analytics/HTTP deps, on-device storage, on-device OCR (ML Kit), donation via `url_launcher` (external, user-tapped), sharing via `share_plus` (user-initiated).
- Effective date on privacy page: **2026-07-06**.
- App display name (verbatim): **ScannerCam Light**.
- Scope `git add` to named paths only — never `git add -A` (repo carries an unrelated WIP pile).
- Run git commands from repo root `/Users/pablohpsilva/Documents/camscanner-light`.
- Commit message trailer for every commit:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j
  ```

---

### Task 1: Scaffold `apps/web/` + design system

**Files:**
- Create: `apps/web/.nojekyll` (empty)
- Create: `apps/web/assets/icon.png` (copy of app icon)
- Create: `apps/web/styles.css`
- Create: `apps/web/index.html` (minimal shell for now: nav + hero)

**Interfaces:**
- Produces: the design-system CSS (custom properties + base classes `.container`, `.btn`, `.btn--primary`, `.nav`, `.hero`, `.device-frame`) that Tasks 3/5/6 reuse; the `<head>` boilerplate pattern (charset, viewport, title, `styles.css` link) copied into every page.

- [ ] **Step 1: Create the folder skeleton and copy the icon**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
mkdir -p apps/web/assets/screenshots
touch apps/web/.nojekyll
cp apps/mobile/assets/icons/scannercam_light_icon_1024.png apps/web/assets/icon.png
```

- [ ] **Step 2: Write `apps/web/styles.css` (design system)**

```css
:root {
  --accent: #2E7DFF;
  --accent-dark: #1E5FD6;
  --ink: #1A2238;
  --bg: #FFFFFF;
  --surface: #F5F8FC;
  --muted: #5B6478;
  --border: #E4EAF2;
  --radius: 16px;
  --shadow: 0 12px 40px rgba(26, 34, 56, 0.12);
  --shadow-sm: 0 4px 16px rgba(26, 34, 56, 0.08);
  --maxw: 1100px;
  --font: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
}

* { box-sizing: border-box; }
html { scroll-behavior: smooth; }
body {
  margin: 0;
  font-family: var(--font);
  color: var(--ink);
  background: var(--bg);
  line-height: 1.6;
  -webkit-font-smoothing: antialiased;
}
a { color: var(--accent); text-decoration: none; }
a:hover { text-decoration: underline; }
img { max-width: 100%; display: block; }

.container { width: 100%; max-width: var(--maxw); margin: 0 auto; padding: 0 24px; }
.section { padding: 72px 0; }
.section--surface { background: var(--surface); }
h1, h2, h3 { line-height: 1.15; letter-spacing: -0.02em; margin: 0 0 0.4em; }
h1 { font-size: clamp(2.2rem, 6vw, 3.6rem); }
h2 { font-size: clamp(1.6rem, 4vw, 2.4rem); }
.lead { font-size: 1.2rem; color: var(--muted); }
.eyebrow { color: var(--accent); font-weight: 700; text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.85rem; }

/* Buttons */
.btn {
  display: inline-flex; align-items: center; gap: 8px;
  padding: 13px 22px; border-radius: 12px; font-weight: 600;
  border: 1px solid var(--border); background: #fff; color: var(--ink);
  cursor: pointer; transition: transform .08s ease, box-shadow .2s ease;
}
.btn:hover { text-decoration: none; box-shadow: var(--shadow-sm); transform: translateY(-1px); }
.btn--primary { background: var(--accent); border-color: var(--accent); color: #fff; }
.btn--primary:hover { background: var(--accent-dark); }
.btn--store { flex-direction: column; align-items: flex-start; padding: 10px 20px; }
.btn--store small { font-size: .7rem; color: var(--muted); font-weight: 500; }
.btn[aria-disabled="true"] { opacity: .75; cursor: default; }
.btn[aria-disabled="true"]:hover { transform: none; box-shadow: none; }

/* Nav */
.nav { position: sticky; top: 0; z-index: 50; background: rgba(255,255,255,.85); backdrop-filter: saturate(180%) blur(12px); border-bottom: 1px solid var(--border); }
.nav__inner { display: flex; align-items: center; justify-content: space-between; height: 64px; }
.nav__brand { display: flex; align-items: center; gap: 10px; font-weight: 700; color: var(--ink); }
.nav__brand img { width: 30px; height: 30px; border-radius: 7px; }
.nav__links { display: flex; align-items: center; gap: 24px; }
.nav__links a { color: var(--ink); font-weight: 500; }
.nav__toggle { display: none; background: none; border: 0; font-size: 1.5rem; cursor: pointer; color: var(--ink); }

/* Hero */
.hero { padding: 64px 0 40px; }
.hero__grid { display: grid; grid-template-columns: 1.1fr 0.9fr; gap: 40px; align-items: center; }
.hero__cta { display: flex; gap: 12px; flex-wrap: wrap; margin: 24px 0; }
.badges { display: flex; gap: 16px; flex-wrap: wrap; margin-top: 12px; color: var(--muted); font-size: .95rem; }
.badges span { display: inline-flex; align-items: center; gap: 6px; }

/* Device frame */
.device-frame {
  background: #0e1220; border-radius: 36px; padding: 12px;
  box-shadow: var(--shadow); max-width: 300px; margin: 0 auto;
}
.device-frame img { border-radius: 26px; width: 100%; }

/* Feature grid */
.grid { display: grid; grid-template-columns: repeat(3, 1fr); gap: 20px; }
.card { background: #fff; border: 1px solid var(--border); border-radius: var(--radius); padding: 24px; box-shadow: var(--shadow-sm); }
.card__icon { width: 44px; height: 44px; border-radius: 12px; background: var(--surface); display: flex; align-items: center; justify-content: center; margin-bottom: 14px; font-size: 1.4rem; }
.card h3 { font-size: 1.15rem; margin-bottom: 6px; }
.card p { color: var(--muted); margin: 0; }

/* Gallery */
.gallery { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 20px; }
.gallery button { border: 0; background: none; padding: 0; cursor: zoom-in; }

/* Privacy band */
.checks { display: grid; grid-template-columns: repeat(4, 1fr); gap: 16px; margin-top: 24px; }
.check { display: flex; align-items: center; gap: 10px; font-weight: 600; }
.check::before { content: "✓"; color: var(--accent); font-weight: 800; }

/* Prose (support/privacy) */
.prose { max-width: 760px; }
.prose h2 { margin-top: 1.6em; }
.prose ul { padding-left: 1.2em; }
.faq { border-top: 1px solid var(--border); }
.faq details { border-bottom: 1px solid var(--border); padding: 16px 0; }
.faq summary { font-weight: 600; cursor: pointer; }
.faq p { color: var(--muted); margin: 10px 0 0; }

/* Footer */
.footer { background: var(--ink); color: #cdd4e4; padding: 48px 0; }
.footer a { color: #fff; }
.footer__grid { display: flex; justify-content: space-between; flex-wrap: wrap; gap: 20px; }

/* Lightbox */
.lightbox { position: fixed; inset: 0; background: rgba(10,14,26,.9); display: none; align-items: center; justify-content: center; z-index: 100; padding: 24px; }
.lightbox.open { display: flex; }
.lightbox img { max-width: 90vw; max-height: 90vh; border-radius: 12px; }

/* Responsive */
@media (max-width: 860px) {
  .hero__grid { grid-template-columns: 1fr; }
  .grid { grid-template-columns: 1fr 1fr; }
  .checks { grid-template-columns: 1fr 1fr; }
  .nav__links { position: absolute; top: 64px; left: 0; right: 0; background: #fff; flex-direction: column; gap: 0; border-bottom: 1px solid var(--border); display: none; }
  .nav__links.open { display: flex; }
  .nav__links a { padding: 14px 24px; width: 100%; border-top: 1px solid var(--border); }
  .nav__toggle { display: block; }
}
@media (max-width: 520px) {
  .grid, .checks { grid-template-columns: 1fr; }
}
```

- [ ] **Step 3: Write a minimal `apps/web/index.html` shell (nav + hero only)**

```html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>ScannerCam Light — Fast, private document scanner</title>
  <meta name="description" content="Scan documents on your phone. On-device, no account, no cloud, works offline. Free." />
  <link rel="icon" href="assets/icon.png" />
  <link rel="stylesheet" href="styles.css" />
</head>
<body>
  <header class="nav">
    <div class="container nav__inner">
      <a class="nav__brand" href="index.html"><img src="assets/icon.png" alt="" /> ScannerCam Light</a>
      <button class="nav__toggle" aria-label="Menu">☰</button>
      <nav class="nav__links">
        <a href="#features">Features</a>
        <a href="#privacy">Privacy</a>
        <a href="support.html">Support</a>
        <a class="btn btn--primary" href="#get">Get the app</a>
      </nav>
    </div>
  </header>

  <main>
    <section class="hero container">
      <div class="hero__grid">
        <div>
          <span class="eyebrow">Document scanner</span>
          <h1>Scan. Clean. Done.</h1>
          <p class="lead">A fast pocket scanner that turns any document into a crisp PDF — and never leaves your phone.</p>
        </div>
        <div class="device-frame">
          <img src="assets/screenshots/placeholder-hero.png" alt="ScannerCam Light app screenshot" />
        </div>
      </div>
    </section>
  </main>
</body>
</html>
```

- [ ] **Step 4: Verify it renders (Playwright)**

Open the file and screenshot at desktop width; confirm nav + hero display and the accent blue button is visible.
Run (via Playwright MCP): navigate to `file:///Users/pablohpsilva/Documents/camscanner-light/apps/web/index.html`, take a screenshot.
Expected: nav bar with brand + blue "Get the app" button, hero headline, empty device frame (broken image ok — real screenshot added in Task 2/3).

- [ ] **Step 5: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/web/.nojekyll apps/web/assets/icon.png apps/web/styles.css apps/web/index.html
git commit -m "feat(web): scaffold marketing site + design system

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j"
```

---

### Task 2: Capture real screenshots from the device

**Files:**
- Create: `apps/web/assets/screenshots/*.png` (raw captures)

**Interfaces:**
- Produces: named screenshot PNGs the landing page references. Final chosen filenames (used by Task 3): `hero.png`, `camera.png`, `library.png`, `page-viewer.png`, `search.png`, `pdf-export.png`. (A `placeholder-hero.png` from Task 1 is replaced by `hero.png`.)

- [ ] **Step 1: Confirm the device is connected**

Run:
```bash
adb devices
```
Expected: `RZCY51D0T1K   device` in the list. If missing, stop and ask the user to connect/unlock the phone.

- [ ] **Step 2: Build & install a Release build, then launch the app**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/mobile
flutter build apk --release && flutter install -d RZCY51D0T1K
```
Then launch the app on the device (tap the icon, or `adb shell monkey -p <package> 1`). Determine package name:
```bash
adb -s RZCY51D0T1K shell pm list packages | grep -i scanner
```
Expected: app opens to the scan/camera or library screen.

- [ ] **Step 3: Seed 1–2 presentable sample documents**

Manually, on the device: scan (or import from gallery) one clean multi-page document with legible text (so OCR/search demos look real). Give it a tidy title. This makes the library grid, page viewer, search, and PDF export screens presentable.
(No automation — this is a curation step. Keep the content generic/non-sensitive.)

- [ ] **Step 4: Capture each screen**

For each target screen, navigate to it on the device, then run:
```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/web/assets/screenshots
adb -s RZCY51D0T1K exec-out screencap -p > raw-camera.png
# repeat, navigating the device between each:
#   raw-camera.png       camera view with edge-detection overlay
#   raw-library.png      library grid with the seeded document(s)
#   raw-page-viewer.png  a single page open in the viewer
#   raw-search.png       search screen showing an OCR text match
#   raw-pdf-export.png   PDF preview / share sheet
#   raw-hero.png         the most attractive single screen for the hero
```

- [ ] **Step 5: Present the batch to the user for curation**

Show all `raw-*.png` to the user (SendUserFile). Ask which to keep and which is the hero. Per the user's answer, copy the chosen files to their final names:
```bash
cd /Users/pablohpsilva/Documents/camscanner-light/apps/web/assets/screenshots
cp raw-hero.png hero.png
cp raw-camera.png camera.png
cp raw-library.png library.png
cp raw-page-viewer.png page-viewer.png
cp raw-search.png search.png
cp raw-pdf-export.png pdf-export.png
rm -f placeholder-hero.png
```
(Adjust the mapping to the user's curation choices.)

- [ ] **Step 6: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/web/assets/screenshots
git commit -m "feat(web): add real device screenshots

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j"
```

---

### Task 3: Build the full landing page

**Files:**
- Modify: `apps/web/index.html` (replace shell with full page)

**Interfaces:**
- Consumes: `styles.css` classes from Task 1; screenshot filenames from Task 2 (`hero.png`, `camera.png`, `library.png`, `page-viewer.png`, `search.png`, `pdf-export.png`).
- Produces: element IDs `#get`, `#features`, `#privacy` that the nav links target; the `.gallery button[data-full]` markup that `main.js` (Task 4) wires to the lightbox.

- [ ] **Step 1: Replace `apps/web/index.html` `<main>` with the full page**

Update the hero image `src` to `assets/screenshots/hero.png`, then insert these sections after the hero and before `</main>` closes. Also add the store buttons + badges inside the hero's text column (after the `.lead`):

```html
          <div class="hero__cta" id="get">
            <span class="btn btn--store" aria-disabled="true"><small>Coming soon on the</small> App Store</span>
            <span class="btn btn--store" aria-disabled="true"><small>Coming soon on</small> Google Play</span>
          </div>
          <div class="badges">
            <span>🔒 On-device</span><span>🙅 No account</span><span>✈️ Offline</span><span>💸 Free</span>
          </div>
```

Sections to add:

```html
    <section class="section section--surface" id="features">
      <div class="container">
        <span class="eyebrow">Everything you need</span>
        <h2>A full scanner in your pocket</h2>
        <div class="grid">
          <div class="card"><div class="card__icon">📐</div><h3>Auto edge detection</h3><p>Finds the page and crops it for you — no fiddly corner dragging.</p></div>
          <div class="card"><div class="card__icon">✨</div><h3>Perspective &amp; enhance</h3><p>Straightens skewed shots and cleans up lighting for a crisp, flat scan.</p></div>
          <div class="card"><div class="card__icon">📚</div><h3>Multi-page documents</h3><p>Combine many pages into one document, reorder and rotate freely.</p></div>
          <div class="card"><div class="card__icon">🔎</div><h3>Search inside scans</h3><p>On-device OCR makes every word findable with fast full-text search.</p></div>
          <div class="card"><div class="card__icon">📄</div><h3>PDF export &amp; share</h3><p>Export a polished PDF and send it anywhere with the system share sheet.</p></div>
          <div class="card"><div class="card__icon">🔁</div><h3>Edit any time</h3><p>Re-crop, rotate, or re-order pages whenever you like — nothing is baked in.</p></div>
        </div>
      </div>
    </section>

    <section class="section">
      <div class="container">
        <span class="eyebrow">See it</span>
        <h2>Real screens, real scans</h2>
        <div class="gallery">
          <button data-full="assets/screenshots/camera.png"><span class="device-frame"><img src="assets/screenshots/camera.png" alt="Camera with edge detection" /></span></button>
          <button data-full="assets/screenshots/library.png"><span class="device-frame"><img src="assets/screenshots/library.png" alt="Document library" /></span></button>
          <button data-full="assets/screenshots/page-viewer.png"><span class="device-frame"><img src="assets/screenshots/page-viewer.png" alt="Page viewer" /></span></button>
          <button data-full="assets/screenshots/search.png"><span class="device-frame"><img src="assets/screenshots/search.png" alt="Full-text search" /></span></button>
          <button data-full="assets/screenshots/pdf-export.png"><span class="device-frame"><img src="assets/screenshots/pdf-export.png" alt="PDF export and share" /></span></button>
        </div>
      </div>
    </section>

    <section class="section section--surface" id="privacy">
      <div class="container">
        <span class="eyebrow">Private by design</span>
        <h2>Your documents never leave your phone</h2>
        <p class="lead">ScannerCam Light has no <code>INTERNET</code> permission on Android and bundles no analytics. Scanning, OCR, and storage all happen on your device.</p>
        <div class="checks">
          <div class="check">Works fully offline</div>
          <div class="check">No account, ever</div>
          <div class="check">No data collected</div>
          <div class="check">Free to use</div>
        </div>
        <p style="margin-top:24px"><a href="privacy.html">Read the full privacy policy →</a></p>
      </div>
    </section>
```

Add the footer just before `</body>` (after `</main>`):

```html
  <footer class="footer">
    <div class="container footer__grid">
      <div><strong>ScannerCam Light</strong><br /><span style="color:#9aa4bd">Scan. Clean. Done.</span></div>
      <div>
        <a href="privacy.html">Privacy</a> &nbsp;·&nbsp;
        <a href="support.html">Support</a> &nbsp;·&nbsp;
        <a href="mailto:scannercamlight.line149@passmail.net">Contact</a>
      </div>
    </div>
  </footer>
  <div class="lightbox" id="lightbox"><img src="" alt="" /></div>
  <script src="main.js"></script>
```

- [ ] **Step 2: Verify with Playwright**

Navigate to `file:///Users/pablohpsilva/Documents/camscanner-light/apps/web/index.html`; screenshot full page at 1280px and at 390px width.
Expected: hero with real screenshot, 6 feature cards (3×2 desktop), gallery of framed screenshots, privacy band with 4 checkmarks, dark footer. Mobile width stacks to one column.

- [ ] **Step 3: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/web/index.html
git commit -m "feat(web): full landing page — hero, features, gallery, privacy

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j"
```

---

### Task 4: Interactions (`main.js`)

**Files:**
- Create: `apps/web/main.js`

**Interfaces:**
- Consumes: `.nav__toggle`, `.nav__links` (Task 1); `.gallery button[data-full]` and `#lightbox` (Task 3).
- Produces: nothing consumed downstream (leaf).

- [ ] **Step 1: Write `apps/web/main.js`**

```js
// Mobile nav toggle
const toggle = document.querySelector('.nav__toggle');
const links = document.querySelector('.nav__links');
if (toggle && links) {
  toggle.addEventListener('click', () => links.classList.toggle('open'));
  links.querySelectorAll('a').forEach((a) =>
    a.addEventListener('click', () => links.classList.remove('open'))
  );
}

// Screenshot lightbox
const lightbox = document.getElementById('lightbox');
if (lightbox) {
  const lbImg = lightbox.querySelector('img');
  document.querySelectorAll('.gallery button[data-full]').forEach((btn) => {
    btn.addEventListener('click', () => {
      lbImg.src = btn.getAttribute('data-full');
      lbImg.alt = btn.querySelector('img')?.alt || '';
      lightbox.classList.add('open');
    });
  });
  lightbox.addEventListener('click', () => lightbox.classList.remove('open'));
  document.addEventListener('keydown', (e) => {
    if (e.key === 'Escape') lightbox.classList.remove('open');
  });
}
```

- [ ] **Step 2: Verify with Playwright**

Navigate to the landing page; click a `.gallery button`; confirm `#lightbox` gains class `open` and shows the enlarged image. Press Escape; confirm it closes. Resize to 390px; click `.nav__toggle`; confirm `.nav__links` gains `open`.
Expected: all three interactions behave as described.

- [ ] **Step 3: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/web/main.js
git commit -m "feat(web): nav toggle + screenshot lightbox

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j"
```

---

### Task 5: Support page

**Files:**
- Create: `apps/web/support.html`

**Interfaces:**
- Consumes: `styles.css` (`.nav`, `.prose`, `.faq`, `.footer`), the nav/footer markup pattern from Task 3.

- [ ] **Step 1: Write `apps/web/support.html`**

Reuse the same `<head>`, `.nav` header, and `.footer` as `index.html` (copy them verbatim, change `<title>` to `Support — ScannerCam Light`). Body main:

```html
  <main class="section">
    <div class="container prose">
      <span class="eyebrow">Support</span>
      <h1>Help &amp; contact</h1>
      <p class="lead">Questions, bugs, or feedback? Email us and we'll get back to you.</p>
      <p><a class="btn btn--primary" href="mailto:scannercamlight.line149@passmail.net">Email support</a></p>

      <h2>Frequently asked questions</h2>
      <div class="faq">
        <details><summary>Does it work offline?</summary><p>Yes. ScannerCam Light does everything on your device and needs no internet connection.</p></details>
        <details><summary>Where are my documents stored?</summary><p>On your phone only. Image files are saved in the app's storage and indexed in a local database — nothing is uploaded.</p></details>
        <details><summary>How do I export a PDF?</summary><p>Open a document, choose export, and use the system share sheet to save or send the PDF anywhere.</p></details>
        <details><summary>Is it free?</summary><p>Yes, it's free. If you'd like to support development, there's an optional donation link inside the app.</p></details>
        <details><summary>How do I free up space?</summary><p>Delete documents you no longer need from the library; their image files are removed from your device.</p></details>
      </div>
    </div>
  </main>
```

- [ ] **Step 2: Verify with Playwright**

Navigate to `file:///Users/pablohpsilva/Documents/camscanner-light/apps/web/support.html`; screenshot. Click a FAQ `<summary>`; confirm the answer expands. Confirm the "Email support" button `href` starts with `mailto:scannercamlight.line149@passmail.net`.
Expected: page renders with nav/footer, FAQ accordions work.

- [ ] **Step 3: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/web/support.html
git commit -m "feat(web): support page with FAQ + contact

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j"
```

---

### Task 6: Privacy policy page

**Files:**
- Create: `apps/web/privacy.html`

**Interfaces:**
- Consumes: `styles.css` (`.nav`, `.prose`, `.footer`), the nav/footer markup pattern from Task 3.

- [ ] **Step 1: Write `apps/web/privacy.html`**

Reuse the same `<head>`, `.nav`, `.footer` (change `<title>` to `Privacy Policy — ScannerCam Light`). Body main:

```html
  <main class="section">
    <div class="container prose">
      <span class="eyebrow">Privacy</span>
      <h1>Privacy Policy</h1>
      <p class="lead">ScannerCam Light is built to keep your documents private. In short: everything stays on your device.</p>
      <p><em>Effective date: 6 July 2026</em></p>

      <h2>What we collect</h2>
      <p><strong>Nothing.</strong> ScannerCam Light does not collect, transmit, or store any personal data on any server. There are no user accounts and no analytics or tracking of any kind.</p>

      <h2>Where your data lives</h2>
      <ul>
        <li>Scanned images are stored as files on your device only.</li>
        <li>Document titles and text are kept in a local database on your device.</li>
        <li>Text recognition (OCR) runs entirely on your device — no images or text are sent anywhere.</li>
      </ul>

      <h2>Network access</h2>
      <p>The Android version requests no <code>INTERNET</code> permission and makes no network requests. The only time an external destination can open is when you deliberately tap the optional donation link, which opens your browser to a third‑party donation page. We don't control or receive data from that page.</p>

      <h2>Sharing</h2>
      <p>When you export or share a document, you choose the destination through your device's own share sheet. That action, and where the file goes, is entirely under your control.</p>

      <h2>Children's privacy</h2>
      <p>Because the app collects no data, it poses no data-collection risk to users of any age.</p>

      <h2>Changes to this policy</h2>
      <p>If this policy changes, the updated version will be posted on this page with a new effective date.</p>

      <h2>Contact</h2>
      <p>Questions? Email <a href="mailto:scannercamlight.line149@passmail.net">scannercamlight.line149@passmail.net</a>.</p>
    </div>
  </main>
```

- [ ] **Step 2: Verify with Playwright**

Navigate to `file:///Users/pablohpsilva/Documents/camscanner-light/apps/web/privacy.html`; screenshot. Confirm headings render and the contact `mailto:` link is present.
Expected: readable policy page with nav/footer.

- [ ] **Step 3: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/web/privacy.html
git commit -m "feat(web): privacy policy page

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j"
```

---

### Task 7: README + GitHub Pages publishing, final verification

**Files:**
- Create: `apps/web/README.md`

**Interfaces:**
- Consumes: all prior files. Leaf task.

- [ ] **Step 1: Write `apps/web/README.md`**

```markdown
# ScannerCam Light — website

Static marketing + support + privacy site for ScannerCam Light. No build step.

## Run locally

    cd apps/web
    python3 -m http.server 8000
    # open http://localhost:8000

Or just open `index.html` in a browser.

## Pages

- `index.html` — marketing landing page
- `support.html` — support / FAQ / contact (App Store & Play "Support URL")
- `privacy.html` — privacy policy (App Store & Play "Privacy Policy URL")

## Publish on GitHub Pages

GitHub Pages can serve a subfolder only from the repo root or `/docs`. Two options:

1. **Pages via GitHub Actions** (recommended): add a workflow that uploads
   `apps/web` as the Pages artifact. Then the site root maps to `apps/web/`.
2. **Publish from a branch**: point Pages at a branch whose root is this folder
   (e.g. a `gh-pages` branch containing the contents of `apps/web/`).

The resulting URLs (replace with the real ones after enabling Pages):

- Marketing: `https://<user>.github.io/<repo>/`
- Support:   `https://<user>.github.io/<repo>/support.html`
- Privacy:   `https://<user>.github.io/<repo>/privacy.html`

Use the Support and Privacy URLs in the App Store Connect / Play Console listing.
```

- [ ] **Step 2: Full-site verification (Playwright)**

For each of `index.html`, `support.html`, `privacy.html` (via `file://` paths):
- Screenshot at 1280px and 390px; confirm layout is correct at both.
- Check console for errors (Playwright console messages) — expect none.
- Check network requests (Playwright network) — expect **only** local `file://` asset loads, **no external hosts**. This proves the offline/no-tracking claim.
- Verify internal links resolve: `index.html` → `support.html`, `privacy.html`; footers link back.

Present the desktop + mobile screenshots of all three pages to the user.
Expected: all pages render, no console errors, zero external requests.

- [ ] **Step 3: Commit**

```bash
cd /Users/pablohpsilva/Documents/camscanner-light
git add apps/web/README.md
git commit -m "docs(web): README + GitHub Pages publishing instructions

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01Cx9MRwUfxcuhpzrSNTGt5j"
```

---

## Notes for the implementer

- The `.nav` header and `.footer` markup repeat across `index.html`, `support.html`, `privacy.html`. Since this is a static site with no templating, copying them is acceptable (KISS) — but keep them identical. If they drift, that's a bug.
- If the device is not connected in Task 2, stop and ask the user rather than shipping placeholder images.
- Do not add web fonts, CDN scripts, or analytics — it would break the verified privacy claim and the offline requirement.
