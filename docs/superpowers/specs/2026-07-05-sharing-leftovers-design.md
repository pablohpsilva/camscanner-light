# Sharing leftovers — link-share + fax (interfaces + graceful-unavailable)

**Date:** 2026-07-05
**Status:** Approved (brainstormed)
**Feature bucket:** 12 Sharing, printing & fax (close-out of the deferred channels)

## Problem

Feature 12 shipped the system share sheet (`SystemShareChannel`) and print. Two
channels were deferred behind interfaces: **share-by-link** and **fax**. Both need
off-device infrastructure the project has deliberately not built:

- **Link-share** needs a backend to upload a file and mint a URL — that is
  Feature 11 (accounts & cloud sync), still deferred. No server ⇒ nothing to link to.
- **Fax** needs a **paid third-party fax provider** (account, API key, per-page cost)
  and would send the user's document **off-device** — a departure from the app's
  on-device privacy posture.

Neither can ship as *working* functionality today. What we can ship now, on-device
and at no cost, is the clean seam plus honest UX: the interfaces (so a real provider
slots in later without touching existing code — OCP), a default "unavailable"
implementation of each, and a share **menu** that surfaces both actions as
not-yet-available. Current state: only `ShareChannel` exists; there is **no
`FaxProvider` type yet**, so the spec's "behind a `ShareChannel`/`FaxProvider`
interface" acceptance criterion is only half-met.

## Scope

**In:** two new interfaces + their Unavailable default impls; one shared share-menu
widget replacing the four per-screen share `IconButton`s; wiring via
`library_dependencies`; unit + widget + BDD tests.

**Out (unchanged deferral):** any real link-minting (needs Feature 11 backend); any
real fax transmission (needs a paid provider + a privacy decision to send documents
off-device). Print is already shipped (N1) and is untouched.

## Design

### Interfaces (new, in `apps/mobile/lib/features/library/`)

**`fax_provider.dart`**
```dart
abstract interface class FaxProvider {
  /// Whether faxing is currently wired to a real provider. False by default.
  bool get isAvailable;

  /// Faxes the already-scrubbed [filePaths] to [faxNumber]. Throws
  /// UnsupportedError when [isAvailable] is false (callers must gate on it).
  Future<void> sendFax({required List<String> filePaths, required String faxNumber});
}

class UnavailableFaxProvider implements FaxProvider {
  const UnavailableFaxProvider();
  @override
  bool get isAvailable => false;
  @override
  Future<void> sendFax({required List<String> filePaths, required String faxNumber}) =>
      throw UnsupportedError('Fax is not available (no provider configured).');
}
```

**`link_share_channel.dart`**
```dart
abstract interface class LinkShareChannel {
  /// Whether link-sharing is wired to a real backend. False by default.
  bool get isAvailable;

  /// Uploads [filePath] and returns a shareable URL. Throws UnsupportedError
  /// when [isAvailable] is false (callers must gate on it).
  Future<Uri> createLink(String filePath);
}

class UnavailableLinkShareChannel implements LinkShareChannel {
  const UnavailableLinkShareChannel();
  @override
  bool get isAvailable => false;
  @override
  Future<Uri> createLink(String filePath) =>
      throw UnsupportedError('Link sharing is not available (no backend configured).');
}
```

**Deviation from the Feature 12 spec (deliberate):** that spec framed link-share as
"just another `ShareChannel` implementation." Link-share returns a **URL**, which does
not fit `ShareChannel.share(List<String>) → void`; forcing it in would overload the
interface (ISP violation). It is therefore a **separate** `LinkShareChannel`.
`ShareChannel` is left untouched.

### Shared menu widget

**`widgets/share_menu_button.dart` — `ShareMenuButton`**, a `PopupMenuButton`
(share icon) that replaces the direct `IconButton(Icons.share, …)` on every screen.
It takes the three channels, the `filePaths`, an optional `subject`, and the set of
actions to show, and renders menu items:

- **Share** → `share.share(filePaths, subject: subject)` — unchanged behavior,
  relocated into the menu.
- **Share link** → if `linkShare.isAvailable`: `createLink(filePaths.first)` then
  (future) hand the resulting URL to the OS share sheet as text; else show a SnackBar
  "Link sharing isn't available yet." (Only the unavailable branch ships now; the
  available branch is behind `isAvailable` and out of scope until the backend exists.)
- **Fax** → if `fax.isAvailable`: (real flow, future); else show a SnackBar
  "Fax isn't available yet."

Items are always **shown and tappable** (not greyed-out): discoverable, testable, and
the *same* code path lights up when a real provider is injected. The
availability-unavailable message uses a shared constant so tests and UI agree.

### Which actions per screen

| Screen | Share | Share link | Fax |
|--------|-------|-----------|-----|
| `pdf_preview_screen` (PDF)        | ✅ | ✅ | ✅ |
| `page_viewer_screen` (page image) | ✅ | ✅ | ✅ |
| `library` (document PDF)          | ✅ | ✅ | ✅ |
| `recognized_text_screen` (.txt)   | ✅ | ✅ | ⛔ |

Fax is omitted on the recognized-text screen — you fax documents/images, not raw
text. `ShareMenuButton` takes a `showFax` flag (default true) to express this.

### Wiring

`library_dependencies.dart` already carries `ShareChannel share = const
SystemShareChannel()`. Add `LinkShareChannel linkShare = const
UnavailableLinkShareChannel()` and `FaxProvider fax = const UnavailableFaxProvider()`,
threaded to the four screens exactly as `share` is today. Injecting a real provider
later is a one-line change with zero UI churn (OCP achieved).

## Data flow

Screen builds `ShareMenuButton(share:, linkShare:, fax:, filePaths:, subject:,
showFax:)` → user opens menu → taps an item → widget either invokes the channel
(available) or shows the shared not-available SnackBar (unavailable). No file leaves
the device in the unavailable path.

## Error handling

- Unavailable channel tapped → SnackBar with the shared not-available message; no throw
  reaches the user (the widget gates on `isAvailable` before calling).
- (Future) available-but-fails → SnackBar error; out of scope now but the gate leaves
  room for it.

## Privacy

No new egress. The unavailable impls send nothing off-device. Files remain the
already-scrubbed Feature 07 exports; the menu adds no metadata path.

## Testing strategy (TDD/BDD first)

- **unit** (`fax_provider_test.dart`, `link_share_channel_test.dart`):
  `UnavailableFaxProvider.isAvailable == false` and `sendFax` throws `UnsupportedError`;
  `UnavailableLinkShareChannel.isAvailable == false` and `createLink` throws. Closes the
  "behind interfaces" acceptance criterion.
- **widget** (`share_menu_button_test.dart`): the menu opens with the expected items;
  tapping **Share** calls a recording fake `ShareChannel` with the given paths/subject;
  tapping **Fax**/**Share link** while unavailable shows the shared SnackBar message and
  does **not** call any channel; `showFax: false` hides the Fax item.
- **per-screen widget/BDD:** existing share tests updated to open the menu then tap
  Share (share still works); one BDD scenario: *Given a PDF, when I open the share menu
  and tap Fax, then a "not available yet" message shows.*

## Deliverable (user-testable)

On any of the four screens, tapping the share icon opens a menu with **Share**,
**Share link**, and (except recognized-text) **Fax**. Share opens the system sheet as
before; Share link / Fax show a clear "not available yet" message. **Test by hand:**
open a PDF, tap share → menu appears; tap Fax → "Fax isn't available yet"; tap Share →
the system share sheet opens with the PDF.

## Acceptance criteria (each closed only by a passing test)

- [ ] `FaxProvider` interface + `UnavailableFaxProvider` exist; `isAvailable` false,
      `sendFax` throws — *unit*.
- [ ] `LinkShareChannel` interface + `UnavailableLinkShareChannel` exist; `isAvailable`
      false, `createLink` throws — *unit*.
- [ ] `ShareMenuButton` renders Share + Share-link (+ Fax unless `showFax:false`);
      Share invokes the injected `ShareChannel` with the file paths/subject — *widget*.
- [ ] Tapping Fax/Share-link while unavailable shows the shared not-available message and
      calls no channel — *widget/BDD*.
- [ ] All four screens use `ShareMenuButton`; the system-share path still works from each
      — *widget/BDD (existing share tests updated, still green)*.
- [ ] `library_dependencies` injects `linkShare`/`fax` defaulting to the Unavailable
      impls; existing on-device channels undisturbed — *unit: wiring*.
- [ ] Full suite green; `flutter analyze` clean — *observed*.

## Non-goals / deferred

- Real link minting (needs the Feature 11 backend).
- Real fax transmission (needs a paid provider + a decision to send documents off-device).
- Print (already shipped, N1) — untouched.

---

> **Definition of Done gate:** per `00-overview-roadmap.md`, not done until every
> criterion above maps to a passing TDD test and (for user-facing behavior) a BDD
> scenario, the full suite is observed green, quality gates pass, and the work is
> reviewed and double-checked.
