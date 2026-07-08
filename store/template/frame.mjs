// Marketing-frame HTML generator for ScannerCam Light store screenshots.
//
// Pure function: given a caption, a raw screenshot (as a data URI), a device
// style and the target canvas size, returns a complete standalone HTML document
// sized to EXACTLY {w}x{h} px. build.mjs renders it with headless Chrome
// (--window-size + --force-device-scale-factor=1) to produce a pixel-exact PNG.

const BRAND = {
  ink: '#1A2238',
  accent: '#2E7DFF',
  accentDark: '#1E5FD6',
};

// Per-device bezel geometry, expressed as fractions of the canvas width so a
// single template scales across iPhone / iPad / Android phone / tablet.
// island/punch are OFF: the OS-level captures already include the real device
// status bar (Dynamic Island / punch-hole), so a faux cutout would double up.
const DEVICE = {
  'ios-iphone': { bezel: 0.028, radius: 0.14, island: false, punch: false, sideMargin: 0.14, topGap: 0.30 },
  'ios-ipad': { bezel: 0.020, radius: 0.045, island: false, punch: false, sideMargin: 0.20, topGap: 0.24 },
  'android-phone': { bezel: 0.024, radius: 0.11, island: false, punch: false, sideMargin: 0.13, topGap: 0.30 },
  'android-tablet': { bezel: 0.018, radius: 0.05, island: false, punch: false, sideMargin: 0.18, topGap: 0.24 },
};

export function buildHtml({ caption, subcaption = '', screenshotDataUri, deviceStyle, w, h }) {
  const d = DEVICE[deviceStyle] ?? DEVICE['ios-iphone'];
  const bezelPx = Math.round(w * d.bezel);
  const radiusOuter = Math.round(w * d.radius);
  const radiusInner = Math.max(0, radiusOuter - bezelPx);
  const sideMargin = Math.round(w * d.sideMargin);
  const topGap = Math.round(h * d.topGap);
  const phoneW = w - sideMargin * 2;
  const capFont = Math.round(w * 0.058);
  const subFont = Math.round(w * 0.030);

  const island = d.island
    ? `<div class="island"></div>`
    : d.punch
      ? `<div class="punch"></div>`
      : '';

  return `<!doctype html><html><head><meta charset="utf-8"><style>
  * { margin:0; padding:0; box-sizing:border-box; }
  html,body { width:${w}px; height:${h}px; overflow:hidden; }
  body {
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;
    -webkit-font-smoothing:antialiased;
    background:
      radial-gradient(120% 80% at 50% -10%, rgba(46,125,255,0.55) 0%, rgba(46,125,255,0) 55%),
      linear-gradient(165deg, ${BRAND.accent} 0%, ${BRAND.accentDark} 30%, ${BRAND.ink} 100%);
    position:relative;
  }
  /* soft decorative blobs */
  .blob { position:absolute; border-radius:50%; filter:blur(${Math.round(w*0.09)}px); opacity:0.35; }
  .blob1 { width:${Math.round(w*0.7)}px; height:${Math.round(w*0.7)}px; background:#5B8Dff; top:${Math.round(h*0.42)}px; left:${-Math.round(w*0.25)}px; }
  .blob2 { width:${Math.round(w*0.6)}px; height:${Math.round(w*0.6)}px; background:#7A5CFF; bottom:${-Math.round(h*0.06)}px; right:${-Math.round(w*0.2)}px; }
  .caption {
    position:absolute; top:${Math.round(h*0.065)}px; left:${Math.round(w*0.09)}px; right:${Math.round(w*0.09)}px;
    text-align:center; color:#fff; z-index:3;
  }
  .caption h1 {
    font-size:${capFont}px; font-weight:800; line-height:1.12; letter-spacing:-0.02em;
    text-shadow:0 2px 20px rgba(0,0,0,0.25);
  }
  .caption p {
    margin-top:${Math.round(w*0.028)}px; font-size:${subFont}px; font-weight:500;
    color:rgba(255,255,255,0.82); line-height:1.3;
  }
  .phone {
    position:absolute; left:${sideMargin}px; top:${topGap}px; width:${phoneW}px;
    background:#0e1220; border-radius:${radiusOuter}px; padding:${bezelPx}px;
    box-shadow:0 ${Math.round(h*0.018)}px ${Math.round(h*0.05)}px rgba(10,14,32,0.55),
               0 0 0 ${Math.max(1,Math.round(w*0.002))}px rgba(255,255,255,0.06) inset;
    z-index:2;
  }
  .screen { position:relative; border-radius:${radiusInner}px; overflow:hidden; background:#fff; }
  .screen img { display:block; width:100%; height:auto; }
  .island {
    position:absolute; top:${Math.round(bezelPx*1.1)}px; left:50%; transform:translateX(-50%);
    width:${Math.round(phoneW*0.34)}px; height:${Math.round(phoneW*0.09)}px;
    background:#0e1220; border-radius:${Math.round(phoneW*0.05)}px; z-index:4;
  }
  .punch {
    position:absolute; top:${Math.round(bezelPx*1.4)}px; left:50%; transform:translateX(-50%);
    width:${Math.round(phoneW*0.035)}px; height:${Math.round(phoneW*0.035)}px;
    background:#0e1220; border-radius:50%; z-index:4;
  }
  </style></head><body>
    <div class="blob blob1"></div><div class="blob blob2"></div>
    <div class="caption"><h1>${caption}</h1>${subcaption ? `<p>${subcaption}</p>` : ''}</div>
    <div class="phone"><div class="screen"><img src="${screenshotDataUri}"/>${island}</div></div>
  </body></html>`;
}

export { BRAND, DEVICE };
