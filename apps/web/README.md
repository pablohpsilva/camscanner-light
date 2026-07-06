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
