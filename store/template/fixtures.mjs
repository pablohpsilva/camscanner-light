// Generate attractive document page images to seed the store-screenshot run.
// Renders each doc's HTML with headless Chrome -> PNG, converts to JPEG (sips),
// then emits a Dart file (base64 constants) the integration test decodes and
// writes into the on-device file store. Keeps all fixtures on-device with no
// asset-bundle bloat.
//
//   node store/template/fixtures.mjs
//
import { execFileSync } from 'node:child_process';
import { writeFileSync, mkdirSync, readFileSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = dirname(fileURLToPath(import.meta.url));
const ROOT = resolve(__dirname, '..', '..');
const OUT = join(ROOT, 'store', '_fixtures');
mkdirSync(OUT, { recursive: true });
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

// Document page size — A4-ish portrait at print-ish density.
const W = 1240, H = 1754;

const page = (inner) => `<!doctype html><html><head><meta charset="utf-8"><style>
  *{margin:0;padding:0;box-sizing:border-box;}
  html,body{width:${W}px;height:${H}px;background:#fff;
    font-family:"Helvetica Neue",Helvetica,Arial,sans-serif;color:#1a2238;}
  .pad{padding:96px 90px;}
  .row{display:flex;justify-content:space-between;align-items:flex-start;}
  h1{font-size:52px;font-weight:800;letter-spacing:-.5px;}
  .brand{font-size:30px;font-weight:800;color:#2E7DFF;}
  .muted{color:#5B6478;font-size:24px;line-height:1.5;}
  table{width:100%;border-collapse:collapse;margin-top:56px;font-size:24px;}
  th{text-align:left;color:#5B6478;font-weight:600;border-bottom:2px solid #E4EAF2;padding:14px 8px;}
  td{padding:16px 8px;border-bottom:1px solid #EEF2F7;}
  .r{text-align:right;} .tot{font-weight:800;font-size:30px;}
  .accent{color:#2E7DFF;}
  .bar{height:8px;background:#2E7DFF;border-radius:4px;margin:0 0 40px;}
  p{font-size:25px;line-height:1.65;color:#2b3348;margin-bottom:22px;}
  h2{font-size:34px;font-weight:800;margin:44px 0 20px;}
  .chip{display:inline-block;background:#EEF3FF;color:#2E7DFF;font-weight:700;
    font-size:20px;padding:8px 18px;border-radius:999px;}
</style></head><body><div class="pad">${inner}</div></body></html>`;

const invoice = page(`
  <div class="bar"></div>
  <div class="row">
    <div><h1>INVOICE</h1><div class="muted">No. INV-2048 · 12 June 2026</div></div>
    <div style="text-align:right"><div class="brand">ACME CORPORATION</div>
      <div class="muted">123 Market Street<br>Springfield</div></div>
  </div>
  <div style="margin-top:48px"><span class="chip">Bill to</span>
    <div class="muted" style="margin-top:16px">Jordan Rivera<br>Rivera Design Studio<br>456 Oak Avenue</div></div>
  <table>
    <tr><th>Description</th><th class="r">Qty</th><th class="r">Unit</th><th class="r">Amount</th></tr>
    <tr><td>Brand identity design</td><td class="r">1</td><td class="r">$1,800</td><td class="r">$1,800</td></tr>
    <tr><td>Website UI mockups</td><td class="r">3</td><td class="r">$420</td><td class="r">$1,260</td></tr>
    <tr><td>Printed brochure layout</td><td class="r">1</td><td class="r">$640</td><td class="r">$640</td></tr>
    <tr><td>Photography licensing</td><td class="r">1</td><td class="r">$300</td><td class="r">$300</td></tr>
    <tr><td class="tot" style="border:none">Total</td><td colspan="2" style="border:none"></td>
        <td class="r tot accent" style="border:none">$4,000</td></tr>
  </table>
  <p class="muted" style="margin-top:80px">Thank you for your business. Payment due within 30 days.</p>`);

const report = page(`
  <div class="brand">ACME CORPORATION</div>
  <h1 style="margin-top:12px">Q2 Final Report</h1>
  <div class="muted" style="margin-bottom:8px">Quarterly performance summary · 2026</div>
  <div class="bar" style="margin-top:28px"></div>
  <p>Revenue grew 24% quarter over quarter, driven by strong demand across the
     design services line and the launch of the new brand identity program.</p>
  <h2>Highlights</h2>
  <p>• Signed 14 new studio clients, up from 9 in Q1.<br>
     • Average project value increased to $4,000.<br>
     • Customer retention held steady at 96%.</p>
  <h2>Outlook</h2>
  <p>We expect momentum to continue into Q3 as the printed brochure and
     photography licensing offerings scale. Investment in tooling should further
     shorten delivery times and lift margins.</p>
  <p class="muted" style="margin-top:56px">Prepared by the Finance team.</p>`);

const receipt = page(`
  <div class="row"><h1>Receipt</h1><div class="brand">Oak Cafe</div></div>
  <div class="muted">Order #5521 · 12 June 2026 · 09:42</div>
  <div class="bar" style="margin-top:28px"></div>
  <table>
    <tr><th>Item</th><th class="r">Qty</th><th class="r">Price</th></tr>
    <tr><td>Flat white</td><td class="r">2</td><td class="r">$9.00</td></tr>
    <tr><td>Almond croissant</td><td class="r">1</td><td class="r">$4.50</td></tr>
    <tr><td>Sparkling water</td><td class="r">1</td><td class="r">$3.00</td></tr>
    <tr><td class="tot" style="border:none">Total</td><td style="border:none"></td>
        <td class="r tot accent" style="border:none">$16.50</td></tr>
  </table>
  <p class="muted" style="margin-top:80px">Thank you — see you again soon!</p>`);

const docs = { invoice, report, receipt };
const dartParts = [];
for (const [name, html] of Object.entries(docs)) {
  const tmp = join(OUT, `${name}.html`);
  const png = join(OUT, `${name}.png`);
  const jpg = join(OUT, `${name}.jpg`);
  writeFileSync(tmp, html);
  execFileSync(CHROME, ['--headless', '--disable-gpu', '--hide-scrollbars',
    '--force-device-scale-factor=1', `--window-size=${W},${H}`,
    `--screenshot=${png}`, `file://${tmp}`], { stdio: 'ignore' });
  execFileSync('sips', ['-s', 'format', 'jpeg', '-s', 'formatOptions', '85', png, '--out', jpg], { stdio: 'ignore' });
  const b64 = readFileSync(jpg).toString('base64');
  dartParts.push(`  '${name}': '${b64}',`);
  console.log('fixture', name, `${(b64.length / 1024).toFixed(0)}KB b64`);
}

const dart = `// GENERATED by store/template/fixtures.mjs — do not edit by hand.
// Base64 JPEG document fixtures decoded + written to the file store by the
// store-screenshot capture harness.
import 'dart:convert';
import 'dart:typed_data';

const Map<String, String> _kStoreFixtureB64 = {
${dartParts.join('\n')}
};

Uint8List storeFixtureBytes(String name) => base64Decode(_kStoreFixtureB64[name]!);
Iterable<String> get storeFixtureNames => _kStoreFixtureB64.keys;
`;
const dartOut = join(ROOT, 'apps/mobile/test/support/store_fixtures.g.dart');
writeFileSync(dartOut, dart);
console.log('wrote', dartOut);
