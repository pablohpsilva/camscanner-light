# iOS IAP Tip Jar — Design

Date: 2026-07-18
Status: Approved (brainstorming) — ready for implementation plan
Branch: `feat/ios-iap-tip-jar`

## Problem & compliance context

The app currently hides **every** donation entry point on iOS — the home-screen
banner, the Settings "Support the app" row, and the whole `DonationScreen` — via
`donationsAvailable` (`defaultTargetPlatform != TargetPlatform.iOS`). This is
required by App Store guideline 3.1.1: donations to the developer must go through
In-App Purchase on iOS, so the external Ko-fi link and the display-only Bitcoin
address are Android-only.

We explicitly evaluated and **rejected** two tempting non-options:

- **Apple Pay (PassKit) for "support the developer."** Apple Pay is for physical
  goods / real-world services (3.1.5(a)) or donations to **verified nonprofits**.
  An individual developer collecting money in-app with nothing delivered is a
  donation under 3.1.1 regardless of what it is labelled ("payment", "support",
  "tip") — Apple reviews substance, not the label. In-app Apple Pay for this
  case is a rejection.
- **Relabelling a donation as "a payment for nothing in return."** Same rejection;
  the label does not change what the transaction is.

The one store-compliant way for an individual developer to collect an in-app
"give money, get nothing back" contribution on iOS is **consumable In-App
Purchase** — a *tip jar*. The StoreKit purchase sheet already uses the user's
stored payment methods (including Wallet cards), so the tap-to-pay UX is
near-identical to Apple Pay. Apple takes the standard 15–30% cut.

## Goal

Add a store-compliant IAP **tip jar** on iOS, replacing the hidden donation
entry points there. **Android is untouched** (keeps Ko-fi + Bitcoin).

## Non-goals (YAGNI)

- No Android IAP (Android keeps the existing external Ko-fi / BTC path).
- No subscriptions, no non-consumables, no "restore purchases" (consumable tips
  need no restore).
- No custom/arbitrary tip amounts (IAP requires fixed, pre-registered products).
- No server-side receipt validation (a tip unlocks nothing; there is nothing to
  protect against a forged receipt — the failure mode is a user tipping for free,
  which is harmless).

## Platform split

- Introduce `tipJarAvailable` = **iOS only** (the mirror of `donationsAvailable`,
  which stays Android-only). Both are simple `defaultTargetPlatform` getters.
- The home-screen banner and the Settings "Support the app" row become visible
  when **either** `donationsAvailable` **or** `tipJarAvailable` is true — i.e.
  visible on both platforms again, each routing to `DonationScreen`.
- `DonationScreen` selects its body by platform:
  - **iOS →** tip-jar mode (three StoreKit tip buttons).
  - **Android →** existing Ko-fi / BTC mode (unchanged).

  One screen, one route (`DonationScreen.route()`), platform-selected body — no
  new navigation surface.

## Products (consumable, repeatable)

Three consumable products, created in App Store Connect:

| Product ID   | Apple price point (approx) |
| ------------ | -------------------------- |
| `tip_small`  | ~$1.99                     |
| `tip_medium` | ~$4.99                     |
| `tip_large`  | ~$9.99                     |

- **Consumable** so a user can tip repeatedly.
- **Prices and display labels come from StoreKit** (`ProductDetails.price`,
  already localized by App Store) — never hardcoded in the app. If a product
  fails to load, its button does not render (no dead/placeholder price).
- Product IDs are defined once as constants in the tip-jar layer (analogous to
  `DonationConfig`), the single source of truth.

## Architecture — injectable `TipJarService` seam

Follows the codebase's existing DI convention (`DonationUrlOpener` /
`DonationClipboardWriter` typedefs, `*Dependencies` classes). We add a small
abstraction so the whole flow is host-testable with a fake and the real StoreKit
path is isolated.

```
abstract class TipJarService {
  Future<List<TipProduct>> loadProducts();     // queries the 3 product IDs
  Future<void> buy(TipProduct product);         // kicks off StoreKit purchase
  Stream<TipEvent> get events;                  // purchase updates
  void dispose();
}
```

- `TipProduct` — id, localized price string, raw `ProductDetails` (or a mapped
  value object) used to start the purchase.
- `TipEvent` — a sealed/enum result: `pending`, `success`, `canceled`, `error`.
- **Real impl** (`StoreKitTipJarService`) wraps `package:in_app_purchase`:
  - Checks `InAppPurchase.instance.isAvailable()`.
  - `queryProductDetails({tip_small, tip_medium, tip_large})`.
  - Listens to `purchaseStream`; on `purchased`/`restored` calls
    `completePurchase` (**consumables must be finished** so the same product can
    be bought again), maps statuses to `TipEvent`s.
  - `error` → `TipEvent.error`; `canceled` → `TipEvent.canceled`; `pending` →
    `TipEvent.pending`.
- **Fake impl** (`FakeTipJarService`, test-only) drives every UI state
  deterministically on host.
- Wired through the donation feature's dependencies (extend the existing
  `LibraryDependencies` factory typedefs, or a small `DonationDependencies` if
  cleaner during implementation) so `main.dart` provides the real service and
  tests inject the fake. Production wiring is the default.

## UI — tip-jar mode states

Rendered inside `DonationScreen` on iOS, reusing the existing header, disclaimer,
"donations grant no benefits" note, and Ream styling / `ReamActionButton`:

1. **Loading** — spinner while `loadProducts()` runs.
2. **Ready** — three tip buttons labelled with StoreKit-localized prices
   (smallest → largest). Tap → `buy()` → StoreKit sheet.
3. **Purchasing / pending** — buttons disabled + progress indicator; a `pending`
   event (e.g. Ask-to-Buy) keeps this state without erroring.
4. **Success** — a **thank-you dialog** (modal "Thank you ❤️" + dismiss).
5. **Canceled** — silent; return to Ready, no error surface.
6. **Error** — error snackbar (reuse `context.showErrorSnack`), return to Ready.
7. **Unavailable** — if the store is unavailable or **no** products load, show a
   friendly "tips are unavailable right now" message instead of dead buttons.

All user-facing strings are localized through the existing `l10n` / ARB pipeline
(new keys added to every ARB, per the i18n guardrails).

## Error handling summary

| Situation                     | Behavior                                        |
| ----------------------------- | ----------------------------------------------- |
| Store unavailable             | Unavailable message; no buttons                 |
| 0 products load               | Unavailable message; no buttons                 |
| Some products load            | Render only the loaded ones                     |
| User cancels sheet            | Silent, back to Ready                           |
| Purchase pending (Ask-to-Buy) | Pending state, no error                         |
| Purchase error                | Error snackbar, back to Ready                   |
| Purchase success              | `completePurchase`, then thank-you dialog       |

## Testing (TDD + BDD, both platforms — non-negotiable)

**Host (fake `TipJarService`):**
- Widget tests + a `.feature` BDD scenario file (with `bdd_widget_test`-generated
  `*_test.dart` and shared steps in `test/step/`) covering: loading → ready,
  buy-success → thank-you dialog, cancel (silent), pending (disabled), error
  (snackbar), store-unavailable / zero-products (unavailable message).
- Platform-gating unit tests: `tipJarAvailable` true only on iOS;
  `DonationScreen` renders tip-jar body on iOS and Ko-fi/BTC body on Android;
  banner + Settings row visible on both platforms.

**Device (per CLAUDE.md both-platforms rule):**
- `integration_test/*_device_test.dart` on a **physical iPhone** with a **sandbox
  tester account**: real StoreKit `queryProductDetails` returns the three
  products with localized prices, a sandbox purchase completes and the thank-you
  dialog appears, and the consumable can be purchased again.
- Android device run confirms the tip jar stays hidden and Ko-fi/BTC are
  unchanged.

Follow TDD: write the failing host test first, watch it fail, implement to green,
refactor. Regenerate `bdd_widget_test` output with `build_runner` after editing
the `.feature`.

## Human prerequisites (cannot be done from code — will be documented as an explicit gap until satisfied)

1. **App Store Connect products.** Create the three consumable IAP products
   (`tip_small`, `tip_medium`, `tip_large`) with metadata + localized display
   names, at the chosen price points, and submit them **with the app build**
   (new IAPs are reviewed alongside a build).
2. **Paid Apps Agreement active.** StoreKit returns **no** products until the
   Paid Applications agreement is signed and active in App Store Connect.
3. **Sandbox tester account** for the on-device purchase test.

Until 1–3 exist, the on-device StoreKit test is a **named gap**, not a silent
one; host tests (fake service) run green regardless.

## Rollout / task decomposition (small, independent, parallelizable)

Independent tasks suitable for parallel subagents (final split decided in the
implementation plan):

- **T1 Platform gate** — add `tipJarAvailable`; update banner + Settings row
  visibility to `donationsAvailable || tipJarAvailable`. Unit tests.
- **T2 Domain types** — `TipProduct`, `TipEvent`, product-ID constants,
  `TipJarService` interface + `FakeTipJarService`. Unit tests. (No plugin dep.)
- **T3 StoreKit impl** — `StoreKitTipJarService` over `in_app_purchase`; add the
  pubspec dependency. Isolated behind T2's interface.
- **T4 Tip-jar UI** — the iOS body + state machine inside `DonationScreen`,
  thank-you dialog, unavailable/error states, l10n keys. Widget + BDD tests
  against the fake. (Depends on T2's interface only.)
- **T5 Wiring** — thread `TipJarService` through the Dependencies class +
  `main.dart` production default. Integration-level host test.
- **T6 Device verification** — iPhone sandbox integration test + Android
  hidden-tip-jar check (gated on the human prerequisites).

T1/T2 are fully independent; T4 depends only on T2's interface; T3 and T5 depend
on T2; T6 depends on the rest + human prereqs.
