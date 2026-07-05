# Donation Banner + Donation Screen — Design

**Date:** 2026-07-05
**App:** `apps/mobile/` (Flutter document scanner)

## Goal

Add a fixed, always-visible banner on the home screen and on the saved-file
viewer screen inviting the user to donate. Tapping the banner opens a donation
screen offering Ko-fi (external browser) and Bitcoin (QR + copyable address).
Donations are voluntary with **no benefits** in return. The feature must comply
with both App Store and Google Play policies.

## Store-safety constraints (the keystone)

- **Ko-fi** opens in the **external browser** (`url_launcher`,
  `LaunchMode.externalApplication`), never an in-app webview that collects
  payment. Apple guideline 3.1.1 permits donations only when collected via an
  external site; in-app payment collection would trigger In-App Purchase.
- **Bitcoin** is **display-only** — a QR code and a copyable address. Payment
  happens in the user's own wallet, outside the app.
- The donation screen shows an explicit disclaimer that the user receives **no
  features, benefits, or content** in return. This keeps the feature out of
  IAP / Google Play Billing requirements on both stores.

## Components

### 1. `lib/features/donation/donation_config.dart`
Single source of swap-later constants:

```dart
class DonationConfig {
  // TODO: set your Ko-fi page, e.g. 'https://ko-fi.com/yourname'
  static const String kofiUrl = '';
  // TODO: set your BTC address
  static const String bitcoinAddress = '';
}
```

An empty string means "not configured yet." Consumers hide/disable the
corresponding UI when the value is empty, so the app never ships a dead button.
No donation values are hardcoded anywhere else.

### 2. `lib/features/donation/donation_banner.dart`
Reusable `StatelessWidget` placed in each Scaffold's `bottomNavigationBar` slot
(reserved space — never scrolls over or overlaps content, the "Scan" FAB, or the
viewer thumbnail strip).

- Always visible, non-dismissible (fixed).
- Warm accent styling (soft amber), `SafeArea`-wrapped, friendly icon
  (coffee/heart).
- Short, appealing copy, e.g. "☕ Enjoying the app? Tap to support it — thank
  you!".
- Whole banner is one tap target → `Navigator.push` to `DonationScreen`.

### 3. `lib/features/donation/donation_screen.dart`
A `Scaffold` screen:

- Title + disclaimer at top: "This is a voluntary donation only. You receive no
  features, benefits, or content in return."
- **Ko-fi section:** button that opens `DonationConfig.kofiUrl` in the external
  browser. Hidden when `kofiUrl` is empty.
- **Bitcoin section:** QR code (`qr_flutter`) of the address; the address as
  selectable text; a **Copy** button (`Clipboard.setData` + confirmation
  SnackBar). Hidden when `bitcoinAddress` is empty.

### 4. Wiring
Add `bottomNavigationBar: const DonationBanner()` to:
- `lib/features/library/home_screen.dart`
- `lib/features/library/page_viewer_screen.dart`

### 5. New dependencies
- `url_launcher`
- `qr_flutter`

## Testing (TDD)

Widget tests:
- Banner renders the support message and has a tappable region.
- Tapping the banner navigates to the donation screen.
- Donation screen renders the "no benefits" disclaimer.
- Copy button writes `DonationConfig.bitcoinAddress` to the clipboard.
- Ko-fi section is hidden when `kofiUrl` is empty; BTC section hidden when
  `bitcoinAddress` is empty.

QR renders in-widget (no file I/O), so no host-test hang risk.

## Out of scope
- Actual Ko-fi handle and BTC address (placeholders now; user fills later).
- Analytics / tracking of donation taps.
- Any dismiss / snooze behavior (banner is intentionally fixed).
