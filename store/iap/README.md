# In-App Purchase assets — tip jar

App Store Connect assets for the iOS tip-jar consumables (`tip_small`,
`tip_medium`, `tip_large`). Both files are 72 dpi, RGB, sRGB profile, flattened
(no alpha), square corners.

| File | Size | App Store Connect field | Notes |
|------|------|-------------------------|-------|
| `tip-jar-promotional-image-1024.png`        | 1024 × 1024 | **App Store Promotion → Promotional Image** (optional) | Promotes the tip on the public product page. |
| `tip-jar-review-screenshot-1290x2796.png`   | 1290 × 2796 | **Review Information → Screenshot** (required to submit) | A valid iPhone 6.9" screenshot size — the review field rejects the 1024×1024 square. |

Both are derived from a real capture of the "Support the app" tip screen; the
review screenshot keeps the exact 1290 × 2796 device resolution (status bar and
home indicator painted out) so App Store Connect accepts it as a screenshot.
