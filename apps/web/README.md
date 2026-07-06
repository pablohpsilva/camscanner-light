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

A GitHub Actions workflow at `.github/workflows/pages.yml` deploys this folder
automatically on every push to `master` that touches `apps/web/**`.

**One-time setup:** in the repo, go to **Settings → Pages → Build and deployment**
and set **Source = "GitHub Actions"**. After the first workflow run, the site is live at:

- Marketing: `https://pablohpsilva.github.io/camscanner-light/`
- Support:   `https://pablohpsilva.github.io/camscanner-light/support.html`
- Privacy:   `https://pablohpsilva.github.io/camscanner-light/privacy.html`

Use the Support and Privacy URLs in the App Store Connect / Play Console listing.

(Alternative, no Actions: point Pages at a `gh-pages` branch whose root holds the
contents of `apps/web/`. The workflow above is the maintained path.)
