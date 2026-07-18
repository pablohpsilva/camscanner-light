# iOS IAP Tip Jar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a store-compliant iOS "tip jar" using consumable In-App Purchases, replacing the currently-hidden donation entry points on iOS; Android's Ko-fi/BTC path is untouched.

**Architecture:** A small injectable `TipJarService` (load products / buy / event stream) wraps `package:in_app_purchase`. `DonationScreen` gains a platform-selected body: an iOS tip-jar `TipJarBody` (StatefulWidget state machine) vs. the existing Android Ko-fi/BTC list. All host tests drive a `FakeTipJarService`; the real StoreKit path is proven on a physical iPhone.

**Tech Stack:** Flutter, Dart, `in_app_purchase` (^3.2.0), `bdd_widget_test`, `flutter_test`, existing Ream theme + `l10n`/ARB pipeline.

## Global Constraints

- All Flutter commands run from `apps/mobile/`, never the repo root.
- **TDD:** failing test first, watch it fail, minimal code to green, refactor. **BDD:** every user-facing behavior has a `.feature` with `bdd_widget_test`-generated `*_test.dart` and steps under `test/step/`; regenerate with `dart run build_runner build --delete-conflicting-outputs`.
- **Both platforms:** native StoreKit behavior must be proven on a real iPhone AND the tip-jar-hidden behavior confirmed on a real Android device — or recorded as an explicit named gap, never silent.
- **Verify then claim:** paste the exact command + green output before saying done.
- `flutter analyze` must stay at **zero warnings**; `dart format lib test` before commit.
- **ARB parity guard** (`test/l10n/arb_parity_test.dart`): every new message key must exist in ALL 11 locale ARBs (`en, pt, pt_BR, es, fr, de, lb, tr, ru, zh, ar`) with identical key sets. Only `app_en.arb` carries `@key` metadata.
- Product IDs are exactly `tip_small`, `tip_medium`, `tip_large` (consumables). Prices/labels come from StoreKit (`ProductDetails.price`) — never hardcode a currency amount in Dart.
- Platform-override cleanup in `testWidgets` uses `try/finally` in the test body, NOT `tearDown`/`addTearDown`.
- Commit messages end with the two trailers this repo uses:
  ```
  Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01BFiiBMDx9N56jyQfi4p7pS
  ```

---

## File Structure

- `lib/features/donation/donation_availability.dart` — **modify:** add `tipJarAvailable` + `donationEntryPointsAvailable`.
- `lib/features/donation/tip_jar/tip_product.dart` — **create:** plugin-free `TipProduct` value object.
- `lib/features/donation/tip_jar/tip_event.dart` — **create:** sealed `TipEvent`.
- `lib/features/donation/tip_jar/tip_product_ids.dart` — **create:** const product-ID list.
- `lib/features/donation/tip_jar/tip_jar_service.dart` — **create:** `TipJarService` interface.
- `lib/features/donation/tip_jar/storekit_tip_jar_service.dart` — **create:** `in_app_purchase` impl + `tipEventFromStatus`.
- `lib/features/donation/tip_jar/tip_jar_body.dart` — **create:** the iOS tip-jar UI state machine.
- `lib/features/donation/donation_screen.dart` — **modify:** select tip-jar vs Ko-fi/BTC body; inject service.
- `lib/features/library/home_screen.dart` — **modify:** banner visibility (lines 244, 491).
- `lib/features/settings/settings_screen.dart` — **modify:** Support row visibility (line 92).
- `lib/l10n/app_*.arb` (×11) — **modify:** 6 new keys.
- `test/support/fake_tip_jar_service.dart` — **create:** scripted fake.
- `test/features/donation/tip_jar_availability_test.dart`, `tip_product_ids_test.dart`, `storekit_tip_event_mapping_test.dart`, `tip_jar_body_test.dart`, `donation_screen_body_selection_test.dart` — **create.**
- `test/features/donation/tip_jar.feature` (+ generated `tip_jar_test.dart`) — **create;** steps in `test/step/`.
- `integration_test/tip_jar_device_test.dart` — **create.**
- `pubspec.yaml` — **modify:** add `in_app_purchase`.

---

## Task 1: Platform gate + entry-point visibility

**Files:**
- Modify: `lib/features/donation/donation_availability.dart`
- Modify: `lib/features/settings/settings_screen.dart:92`
- Modify: `lib/features/library/home_screen.dart:244,491`
- Test: `test/features/donation/tip_jar_availability_test.dart`

**Interfaces:**
- Produces: `bool get tipJarAvailable` (true only on iOS); `bool get donationEntryPointsAvailable` (`donationsAvailable || tipJarAvailable`). `donationsAvailable` is unchanged (Android-only, gates the Ko-fi/BTC body).

- [ ] **Step 1: Write the failing test**

Create `test/features/donation/tip_jar_availability_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_availability.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test('tipJarAvailable is true only on iOS', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(tipJarAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(tipJarAvailable, isFalse);
  });

  test('donationsAvailable is true only on Android (Ko-fi/BTC)', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(donationsAvailable, isFalse);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(donationsAvailable, isTrue);
  });

  test('donationEntryPointsAvailable is true on both platforms', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    expect(donationEntryPointsAvailable, isTrue);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    expect(donationEntryPointsAvailable, isTrue);
  });
}
```

(Package import prefix is `mobile` — confirm against an existing test's import, e.g. `package:mobile/...`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/donation/tip_jar_availability_test.dart`
Expected: FAIL — `tipJarAvailable`/`donationEntryPointsAvailable` undefined.

- [ ] **Step 3: Implement the getters**

Replace `lib/features/donation/donation_availability.dart` with:

```dart
import 'package:flutter/foundation.dart';

/// Whether the EXTERNAL donation options (Ko-fi link + Bitcoin) may be shown.
///
/// App Store guideline 3.1.1: donations to the developer must go through
/// In-App Purchase on iOS/iPadOS, so the external Ko-fi/Bitcoin body is
/// Android-only. iOS uses the IAP tip jar instead (see [tipJarAvailable]).
bool get donationsAvailable => defaultTargetPlatform != TargetPlatform.iOS;

/// Whether the store-compliant IAP tip jar may be shown. iOS-only: on iOS the
/// only compliant "give money, get nothing back" path is consumable IAP.
bool get tipJarAvailable => defaultTargetPlatform == TargetPlatform.iOS;

/// Whether ANY donation entry point (home banner + Settings "Support the app"
/// row) should be visible. Both platforms now have a compliant path, so both
/// show an entry point; the destination screen picks the right body.
bool get donationEntryPointsAvailable => donationsAvailable || tipJarAvailable;
```

- [ ] **Step 4: Wire the entry points to the combined getter**

In `lib/features/settings/settings_screen.dart` line 92, change `if (donationsAvailable)` → `if (donationEntryPointsAvailable)`.

In `lib/features/library/home_screen.dart` line 244, change `final banner = donationsAvailable ? const DonationBanner() : null;` → `final banner = donationEntryPointsAvailable ? const DonationBanner() : null;`.

In `lib/features/library/home_screen.dart` line 491, change `donationsAvailable ? 8 : 16` → `donationEntryPointsAvailable ? 8 : 16`.

- [ ] **Step 5: Run tests to verify green + analyze**

Run: `flutter test test/features/donation/tip_jar_availability_test.dart && flutter analyze`
Expected: PASS, zero analyzer issues.

- [ ] **Step 6: Commit**

```bash
dart format lib/features/donation/donation_availability.dart lib/features/settings/settings_screen.dart lib/features/library/home_screen.dart test/features/donation/tip_jar_availability_test.dart
git add lib/features/donation/donation_availability.dart lib/features/settings/settings_screen.dart lib/features/library/home_screen.dart test/features/donation/tip_jar_availability_test.dart
git commit -m "feat(donation): show donation entry points on iOS via tipJarAvailable gate"
```

---

## Task 2: Domain types (plugin-free) + service interface + fake

**Files:**
- Create: `lib/features/donation/tip_jar/tip_product.dart`
- Create: `lib/features/donation/tip_jar/tip_event.dart`
- Create: `lib/features/donation/tip_jar/tip_product_ids.dart`
- Create: `lib/features/donation/tip_jar/tip_jar_service.dart`
- Create: `test/support/fake_tip_jar_service.dart`
- Test: `test/features/donation/tip_product_ids_test.dart`

**Interfaces:**
- Produces:
  - `class TipProduct { final String id; final String price; const TipProduct({required this.id, required this.price}); }`
  - `sealed class TipEvent` with `const TipEventPending()`, `const TipEventSuccess()`, `const TipEventCanceled()`, `const TipEventError()`.
  - `const List<String> kTipProductIds = ['tip_small', 'tip_medium', 'tip_large'];`
  - `abstract class TipJarService { Future<List<TipProduct>> loadProducts(); Future<void> buy(TipProduct product); Stream<TipEvent> get events; void dispose(); }`
  - `class FakeTipJarService implements TipJarService` (test support) with `scriptProducts(List<TipProduct>)` and `scriptNextBuy(List<TipEvent>)`.
- These names are consumed by Tasks 3 (impl), 4 (UI), 5 (wiring).

- [ ] **Step 1: Write the failing test**

Create `test/features/donation/tip_product_ids_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/tip_jar/tip_product_ids.dart';

void main() {
  test('exactly the three consumable tip product ids in ascending order', () {
    expect(kTipProductIds, ['tip_small', 'tip_medium', 'tip_large']);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/features/donation/tip_product_ids_test.dart`
Expected: FAIL — file/const not found.

- [ ] **Step 3: Create the domain types**

Create `lib/features/donation/tip_jar/tip_product_ids.dart`:

```dart
/// The three consumable IAP product identifiers, ascending by price. Must match
/// the products created in App Store Connect exactly. This is the single source
/// of truth — do not hardcode a product id anywhere else.
const List<String> kTipProductIds = ['tip_small', 'tip_medium', 'tip_large'];
```

Create `lib/features/donation/tip_jar/tip_product.dart`:

```dart
/// A purchasable tip, plugin-free so the domain and tests never depend on
/// `in_app_purchase`. [price] is the StoreKit-localized display string (e.g.
/// "$1.99", "1,99 €") — never a hardcoded amount.
class TipProduct {
  const TipProduct({required this.id, required this.price});

  final String id;
  final String price;
}
```

Create `lib/features/donation/tip_jar/tip_event.dart`:

```dart
/// A purchase-flow update from the store, mapped to a plugin-free type.
sealed class TipEvent {
  const TipEvent();
}

/// The purchase is awaiting external action (e.g. Ask-to-Buy approval).
class TipEventPending extends TipEvent {
  const TipEventPending();
}

/// The purchase completed and was acknowledged to the store.
class TipEventSuccess extends TipEvent {
  const TipEventSuccess();
}

/// The user dismissed/cancelled the store sheet. Not an error.
class TipEventCanceled extends TipEvent {
  const TipEventCanceled();
}

/// The purchase failed.
class TipEventError extends TipEvent {
  const TipEventError();
}
```

Create `lib/features/donation/tip_jar/tip_jar_service.dart`:

```dart
import 'tip_event.dart';
import 'tip_product.dart';

/// Loads tip products and drives consumable purchases. Injectable so the UI is
/// host-testable with a fake while the real StoreKit path stays isolated.
abstract class TipJarService {
  /// Returns the available tip products (ascending price), or an empty list if
  /// the store is unavailable or no products resolve.
  Future<List<TipProduct>> loadProducts();

  /// Starts a consumable purchase for [product]. Results arrive on [events].
  Future<void> buy(TipProduct product);

  /// Purchase-flow updates (pending / success / canceled / error).
  Stream<TipEvent> get events;

  /// Cancels the store subscription and closes the event stream.
  void dispose();
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/features/donation/tip_product_ids_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the fake + a test that exercises it**

Create `test/support/fake_tip_jar_service.dart`:

```dart
import 'dart:async';

import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/tip_jar_service.dart';
import 'package:mobile/features/donation/tip_jar/tip_product.dart';

/// Deterministic [TipJarService] for host tests. Script the products
/// [loadProducts] returns and the sequence of [TipEvent]s the next [buy] emits.
class FakeTipJarService implements TipJarService {
  FakeTipJarService({List<TipProduct> products = _defaultProducts})
    : _products = products;

  static const _defaultProducts = <TipProduct>[
    TipProduct(id: 'tip_small', price: r'$1.99'),
    TipProduct(id: 'tip_medium', price: r'$4.99'),
    TipProduct(id: 'tip_large', price: r'$9.99'),
  ];

  List<TipProduct> _products;
  List<TipEvent> _nextBuy = const [TipEventSuccess()];
  bool _throwOnLoad = false;
  final _controller = StreamController<TipEvent>.broadcast();

  int buyCount = 0;
  TipProduct? lastBought;

  void scriptProducts(List<TipProduct> products) => _products = products;
  void scriptNextBuy(List<TipEvent> events) => _nextBuy = events;
  void scriptLoadThrows() => _throwOnLoad = true;

  @override
  Future<List<TipProduct>> loadProducts() async {
    if (_throwOnLoad) throw StateError('store down');
    return _products;
  }

  @override
  Future<void> buy(TipProduct product) async {
    buyCount++;
    lastBought = product;
    for (final e in _nextBuy) {
      _controller.add(e);
    }
  }

  @override
  Stream<TipEvent> get events => _controller.stream;

  @override
  void dispose() => _controller.close();
}
```

Append to `test/features/donation/tip_product_ids_test.dart` a second file `test/support/fake_tip_jar_service_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/tip_product.dart';

import 'fake_tip_jar_service.dart';

void main() {
  test('buy emits the scripted event sequence and records the product', () async {
    final fake = FakeTipJarService();
    fake.scriptNextBuy(const [TipEventPending(), TipEventSuccess()]);
    final events = <TipEvent>[];
    fake.events.listen(events.add);

    const product = TipProduct(id: 'tip_small', price: r'$1.99');
    await fake.buy(product);
    await Future<void>.delayed(Duration.zero);

    expect(fake.buyCount, 1);
    expect(fake.lastBought, product);
    expect(events, [isA<TipEventPending>(), isA<TipEventSuccess>()]);
    fake.dispose();
  });

  test('loadProducts returns scripted list', () async {
    final fake = FakeTipJarService()..scriptProducts(const []);
    expect(await fake.loadProducts(), isEmpty);
    fake.dispose();
  });
}
```

- [ ] **Step 6: Run tests to verify green + analyze**

Run: `flutter test test/features/donation/tip_product_ids_test.dart test/support/fake_tip_jar_service_test.dart && flutter analyze`
Expected: PASS, zero issues.

- [ ] **Step 7: Commit**

```bash
dart format lib/features/donation/tip_jar test/support/fake_tip_jar_service.dart test/features/donation/tip_product_ids_test.dart test/support/fake_tip_jar_service_test.dart
git add lib/features/donation/tip_jar test/support/fake_tip_jar_service.dart test/features/donation/tip_product_ids_test.dart test/support/fake_tip_jar_service_test.dart
git commit -m "feat(donation): tip-jar domain types, service interface, and fake"
```

---

## Task 3: StoreKit implementation over `in_app_purchase`

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (add `in_app_purchase: ^3.2.0`)
- Create: `lib/features/donation/tip_jar/storekit_tip_jar_service.dart`
- Test: `test/features/donation/storekit_tip_event_mapping_test.dart`

**Interfaces:**
- Consumes: `TipJarService`, `TipProduct`, `TipEvent*`, `kTipProductIds` (Task 2).
- Produces:
  - `class StoreKitTipJarService implements TipJarService` with `StoreKitTipJarService({InAppPurchase? iap})`.
  - `TipEvent tipEventFromStatus(PurchaseStatus status)` — pure mapper, unit-tested on host.

- [ ] **Step 1: Add the dependency**

Run from `apps/mobile/`:
```bash
flutter pub add in_app_purchase
flutter pub get
```
Confirm `pubspec.yaml` pins a `^3.x` constraint (e.g. `in_app_purchase: ^3.2.0`). If `pub add` resolves to a different major, pin `in_app_purchase: ^3.2.0` explicitly and re-run `flutter pub get`.

- [ ] **Step 2: Write the failing mapper test**

Create `test/features/donation/storekit_tip_event_mapping_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/storekit_tip_jar_service.dart';

void main() {
  test('maps PurchaseStatus to TipEvent', () {
    expect(tipEventFromStatus(PurchaseStatus.pending), isA<TipEventPending>());
    expect(tipEventFromStatus(PurchaseStatus.purchased), isA<TipEventSuccess>());
    expect(tipEventFromStatus(PurchaseStatus.restored), isA<TipEventSuccess>());
    expect(tipEventFromStatus(PurchaseStatus.canceled), isA<TipEventCanceled>());
    expect(tipEventFromStatus(PurchaseStatus.error), isA<TipEventError>());
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/features/donation/storekit_tip_event_mapping_test.dart`
Expected: FAIL — `tipEventFromStatus`/`StoreKitTipJarService` undefined.

- [ ] **Step 4: Implement the service + mapper**

Create `lib/features/donation/tip_jar/storekit_tip_jar_service.dart`:

```dart
import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

import 'tip_event.dart';
import 'tip_jar_service.dart';
import 'tip_product.dart';
import 'tip_product_ids.dart';

/// Pure mapping from a StoreKit/Play [PurchaseStatus] to our plugin-free
/// [TipEvent]. Host-testable — no platform channel is touched.
TipEvent tipEventFromStatus(PurchaseStatus status) {
  switch (status) {
    case PurchaseStatus.pending:
      return const TipEventPending();
    case PurchaseStatus.purchased:
    case PurchaseStatus.restored:
      return const TipEventSuccess();
    case PurchaseStatus.canceled:
      return const TipEventCanceled();
    case PurchaseStatus.error:
      return const TipEventError();
  }
}

/// Real [TipJarService] backed by `in_app_purchase`. Consumable purchases are
/// finished with `completePurchase` so the same tip can be given again (an
/// unfinished iOS transaction is redelivered forever).
class StoreKitTipJarService implements TipJarService {
  StoreKitTipJarService({InAppPurchase? iap})
    : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;
  final _events = StreamController<TipEvent>.broadcast();
  final Map<String, ProductDetails> _detailsById = {};
  StreamSubscription<List<PurchaseDetails>>? _sub;

  @override
  Stream<TipEvent> get events => _events.stream;

  @override
  Future<List<TipProduct>> loadProducts() async {
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (_) => _emit(const TipEventError()),
    );
    if (!await _iap.isAvailable()) return const [];
    final response = await _iap.queryProductDetails(kTipProductIds.toSet());
    _detailsById
      ..clear()
      ..addEntries(response.productDetails.map((p) => MapEntry(p.id, p)));
    final products = response.productDetails
        .map((p) => TipProduct(id: p.id, price: p.price))
        .toList()
      ..sort(
        (a, b) => kTipProductIds.indexOf(a.id) - kTipProductIds.indexOf(b.id),
      );
    return products;
  }

  @override
  Future<void> buy(TipProduct product) async {
    final details = _detailsById[product.id];
    if (details == null) {
      _emit(const TipEventError());
      return;
    }
    await _iap.buyConsumable(
      purchaseParam: PurchaseParam(productDetails: details),
    );
  }

  void _onPurchases(List<PurchaseDetails> purchases) {
    for (final purchase in purchases) {
      _emit(tipEventFromStatus(purchase.status));
      if (purchase.pendingCompletePurchase) {
        // Consumable: finish so it can be purchased again (and to avoid
        // Android auto-refunds / iOS redelivery).
        _iap.completePurchase(purchase);
      }
    }
  }

  void _emit(TipEvent event) {
    if (!_events.isClosed) _events.add(event);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _events.close();
  }
}
```

- [ ] **Step 5: Run test to verify it passes + analyze**

Run: `flutter test test/features/donation/storekit_tip_event_mapping_test.dart && flutter analyze`
Expected: PASS, zero issues. (If the analyzer flags the `switch` as needing a default, it means a new `PurchaseStatus` value exists — add a branch, do not add a `default`, so future additions stay exhaustive.)

- [ ] **Step 6: Commit**

```bash
dart format lib/features/donation/tip_jar/storekit_tip_jar_service.dart test/features/donation/storekit_tip_event_mapping_test.dart pubspec.yaml
git add lib/features/donation/tip_jar/storekit_tip_jar_service.dart test/features/donation/storekit_tip_event_mapping_test.dart pubspec.yaml pubspec.lock
git commit -m "feat(donation): StoreKit tip-jar service over in_app_purchase"
```

---

## Task 4: Tip-jar UI + localization + BDD

**Files:**
- Modify: `lib/l10n/app_en.arb` (+ `@` metadata) and the other 10 ARBs
- Create: `lib/features/donation/tip_jar/tip_jar_body.dart`
- Modify: `lib/features/donation/donation_screen.dart`
- Test: `test/features/donation/tip_jar_body_test.dart`, `test/features/donation/donation_screen_body_selection_test.dart`
- Create: `test/features/donation/tip_jar.feature` (+ generated `tip_jar_test.dart`), steps under `test/step/`

**Interfaces:**
- Consumes: `TipJarService`, `TipProduct`, `TipEvent*` (Task 2); `tipJarAvailable` (Task 1).
- Produces:
  - `class TipJarBody extends StatefulWidget { const TipJarBody({super.key, required this.createService}); final TipJarService Function() createService; }`
  - `DonationScreen` gains `{TipJarService Function()? createTipJar, bool? tipJarMode}`; `DonationScreen.route({TipJarService Function()? createTipJar, bool? tipJarMode})`.
- l10n keys: `donationTipButtonLabel` (placeholder `price`), `donationTipThankYouTitle`, `donationTipThankYouBody`, `donationTipThankYouClose`, `donationTipUnavailable`, `donationTipError`.

- [ ] **Step 1: Add the six l10n keys to every ARB**

In `lib/l10n/app_en.arb`, add these messages (with `@` metadata) alongside the existing `donation*` keys:

```json
"donationTipButtonLabel": "Tip {price}",
"@donationTipButtonLabel": {
  "description": "Tip jar button; {price} is the StoreKit-localized price",
  "placeholders": { "price": { "type": "String" } }
},
"donationTipThankYouTitle": "Thank you ❤️",
"@donationTipThankYouTitle": { "description": "Tip success dialog title" },
"donationTipThankYouBody": "Your support keeps this app going.",
"@donationTipThankYouBody": { "description": "Tip success dialog body" },
"donationTipThankYouClose": "Close",
"@donationTipThankYouClose": { "description": "Dismiss the tip thank-you dialog" },
"donationTipUnavailable": "Tips aren't available right now. Please try again later.",
"@donationTipUnavailable": { "description": "Shown when the store or products fail to load" },
"donationTipError": "Couldn't complete your tip",
"@donationTipError": { "description": "Snackbar when a tip purchase fails" }
```

Add the **same six keys** (values only, no `@`) to the other 10 ARBs with these translations:

| key | pt | pt_BR | es | fr | de |
| --- | --- | --- | --- | --- | --- |
| donationTipButtonLabel | `Gorjeta {price}` | `Gorjeta {price}` | `Propina {price}` | `Pourboire {price}` | `Trinkgeld {price}` |
| donationTipThankYouTitle | `Obrigado ❤️` | `Obrigado ❤️` | `Gracias ❤️` | `Merci ❤️` | `Danke ❤️` |
| donationTipThankYouBody | `O teu apoio mantém esta aplicação a funcionar.` | `Seu apoio mantém este app funcionando.` | `Tu apoyo mantiene esta app en marcha.` | `Votre soutien fait vivre cette application.` | `Deine Unterstützung hält diese App am Laufen.` |
| donationTipThankYouClose | `Fechar` | `Fechar` | `Cerrar` | `Fermer` | `Schließen` |
| donationTipUnavailable | `As gorjetas não estão disponíveis de momento. Tenta novamente mais tarde.` | `As gorjetas não estão disponíveis no momento. Tente novamente mais tarde.` | `Las propinas no están disponibles ahora mismo. Inténtalo de nuevo más tarde.` | `Les pourboires ne sont pas disponibles pour le moment. Réessayez plus tard.` | `Trinkgelder sind derzeit nicht verfügbar. Bitte versuche es später erneut.` |
| donationTipError | `Não foi possível concluir a gorjeta` | `Não foi possível concluir a gorjeta` | `No se pudo completar la propina` | `Impossible de finaliser le pourboire` | `Trinkgeld konnte nicht abgeschlossen werden` |

| key | lb | tr | ru | zh | ar |
| --- | --- | --- | --- | --- | --- |
| donationTipButtonLabel | `Pourboire {price}` | `Bahşiş {price}` | `Чаевые {price}` | `打赏 {price}` | `إكرامية {price}` |
| donationTipThankYouTitle | `Merci ❤️` | `Teşekkürler ❤️` | `Спасибо ❤️` | `谢谢 ❤️` | `شكرًا ❤️` |
| donationTipThankYouBody | `Däin Ënnerstëtzung hält dës App um Lafen.` | `Desteğin bu uygulamayı ayakta tutuyor.` | `Ваша поддержка помогает развивать приложение.` | `你的支持让这个应用持续运行。` | `دعمك يبقي هذا التطبيق مستمرًا.` |
| donationTipThankYouClose | `Zoumaachen` | `Kapat` | `Закрыть` | `关闭` | `إغلاق` |
| donationTipUnavailable | `Pourboiren sinn am Moment net verfügbar. Probéier w.e.g. méi spéit nach eng Kéier.` | `Bahşişler şu anda kullanılamıyor. Lütfen daha sonra tekrar deneyin.` | `Чаевые сейчас недоступны. Попробуйте позже.` | `打赏暂时不可用，请稍后再试。` | `الإكراميات غير متوفرة حاليًا. حاول مرة أخرى لاحقًا.` |
| donationTipError | `Não foi possível concluir a gorjeta`→ use `De Pourboire konnt net ofgeschloss ginn` | `Bahşiş tamamlanamadı` | `Не удалось отправить чаевые` | `无法完成打赏` | `تعذّر إتمام الإكرامية` |

(The lb `donationTipError` value is `De Pourboire konnt net ofgeschloss ginn`.)

Regenerate localizations:
```bash
flutter gen-l10n
```

- [ ] **Step 2: Verify ARB parity stays green**

Run: `flutter test test/l10n/arb_parity_test.dart`
Expected: PASS (all 11 locales have identical key sets). If it fails listing missing keys, add them to the named locale.

- [ ] **Step 3: Write the failing widget tests**

Create `test/features/donation/tip_jar_body_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/tip_jar/tip_event.dart';
import 'package:mobile/features/donation/tip_jar/tip_jar_body.dart';
import 'package:mobile/features/donation/tip_jar/tip_product.dart';
import 'package:mobile/l10n/l10n.dart';

import '../../support/fake_tip_jar_service.dart';
import '../../support/localized_test_app.dart'; // existing l10n test harness

Widget _host(FakeTipJarService fake) => localizedTestApp(
  home: Scaffold(body: TipJarBody(createService: () => fake)),
);

void main() {
  testWidgets('renders a button per product with its StoreKit price',
      (tester) async {
    final fake = FakeTipJarService();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    expect(find.textContaining(r'$1.99'), findsOneWidget);
    expect(find.textContaining(r'$4.99'), findsOneWidget);
    expect(find.textContaining(r'$9.99'), findsOneWidget);
    fake.dispose();
  });

  testWidgets('tapping a tip buys it and shows the thank-you dialog',
      (tester) async {
    final fake = FakeTipJarService()..scriptNextBuy(const [TipEventSuccess()]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining(r'$1.99'));
    await tester.pumpAndSettle();

    expect(fake.buyCount, 1);
    expect(fake.lastBought?.id, 'tip_small');
    expect(find.byKey(const Key('tip-thank-you-dialog')), findsOneWidget);
    fake.dispose();
  });

  testWidgets('canceled purchase shows no dialog and no error', (tester) async {
    final fake = FakeTipJarService()..scriptNextBuy(const [TipEventCanceled()]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(r'$1.99'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-thank-you-dialog')), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    fake.dispose();
  });

  testWidgets('error purchase shows an error snackbar', (tester) async {
    final fake = FakeTipJarService()..scriptNextBuy(const [TipEventError()]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining(r'$1.99'));
    await tester.pump(); // let the snackbar appear

    expect(find.byType(SnackBar), findsOneWidget);
    fake.dispose();
  });

  testWidgets('no products shows the unavailable message', (tester) async {
    final fake = FakeTipJarService()..scriptProducts(const <TipProduct>[]);
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-unavailable')), findsOneWidget);
    expect(find.textContaining(r'$'), findsNothing);
    fake.dispose();
  });

  testWidgets('loadProducts throwing shows the unavailable message',
      (tester) async {
    final fake = FakeTipJarService()..scriptLoadThrows();
    await tester.pumpWidget(_host(fake));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-unavailable')), findsOneWidget);
    fake.dispose();
  });
}
```

(Confirm the localized-test-app helper name/path against an existing widget test that pumps `context.l10n`; the i18n memory calls it `localizedTestApp`. If the signature differs, match the existing one.)

- [ ] **Step 4: Run tests to verify they fail**

Run: `flutter test test/features/donation/tip_jar_body_test.dart`
Expected: FAIL — `TipJarBody` undefined.

- [ ] **Step 5: Implement `TipJarBody`**

Create `lib/features/donation/tip_jar/tip_jar_body.dart`:

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/ui/error_snack.dart';
import '../../../l10n/l10n.dart';
import '../../../theme/ream_colors.dart';
import '../../../theme/widgets/ream_action_button.dart';
import 'tip_event.dart';
import 'tip_jar_service.dart';
import 'tip_product.dart';

/// iOS tip-jar body: loads consumable products and drives purchases through a
/// [TipJarService]. Success shows a thank-you dialog; cancel is silent; error
/// shows a snackbar; an unavailable store shows a friendly message (no dead
/// buttons).
class TipJarBody extends StatefulWidget {
  const TipJarBody({super.key, required this.createService});

  final TipJarService Function() createService;

  @override
  State<TipJarBody> createState() => _TipJarBodyState();
}

enum _Phase { loading, ready, purchasing, unavailable }

class _TipJarBodyState extends State<TipJarBody> {
  late final TipJarService _service = widget.createService();
  StreamSubscription<TipEvent>? _sub;
  _Phase _phase = _Phase.loading;
  List<TipProduct> _products = const [];

  @override
  void initState() {
    super.initState();
    _sub = _service.events.listen(_onEvent);
    _load();
  }

  Future<void> _load() async {
    try {
      final products = await _service.loadProducts();
      if (!mounted) return;
      setState(() {
        _products = products;
        _phase = products.isEmpty ? _Phase.unavailable : _Phase.ready;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _phase = _Phase.unavailable);
    }
  }

  void _onEvent(TipEvent event) {
    if (!mounted) return;
    switch (event) {
      case TipEventPending():
        setState(() => _phase = _Phase.purchasing);
      case TipEventSuccess():
        setState(() => _phase = _Phase.ready);
        _showThankYou();
      case TipEventCanceled():
        setState(() => _phase = _Phase.ready);
      case TipEventError():
        setState(() => _phase = _Phase.ready);
        context.showErrorSnack(context.l10n.donationTipError);
    }
  }

  Future<void> _buy(TipProduct product) async {
    setState(() => _phase = _Phase.purchasing);
    await _service.buy(product);
  }

  Future<void> _showThankYou() {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('tip-thank-you-dialog'),
        title: Text(context.l10n.donationTipThankYouTitle),
        content: Text(context.l10n.donationTipThankYouBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.l10n.donationTipThankYouClose),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    switch (_phase) {
      case _Phase.loading:
        return const Center(child: CircularProgressIndicator());
      case _Phase.unavailable:
        return Padding(
          key: const Key('tip-unavailable'),
          padding: const EdgeInsets.all(24),
          child: Text(
            context.l10n.donationTipUnavailable,
            textAlign: TextAlign.center,
            style: TextStyle(color: r.ink2, height: 1.5),
          ),
        );
      case _Phase.ready:
      case _Phase.purchasing:
        final busy = _phase == _Phase.purchasing;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final product in _products) ...[
              ReamActionButton(
                key: Key('tip-button-${product.id}'),
                label: context.l10n.donationTipButtonLabel(product.price),
                icon: Icons.favorite,
                primary: true,
                fillColor: r.kofiRed,
                onPressed: busy ? null : () => _buy(product),
              ),
              const SizedBox(height: 11),
            ],
            if (busy) const CircularProgressIndicator(),
          ],
        );
    }
  }
}
```

(If `ReamActionButton.onPressed` is non-nullable, wrap disabling differently — e.g. omit the button's tap when `busy` — but keep the disabled affordance. Check the widget's signature in `lib/theme/widgets/ream_action_button.dart` before finalizing.)

- [ ] **Step 6: Run the widget tests to green**

Run: `flutter test test/features/donation/tip_jar_body_test.dart`
Expected: PASS (all six).

- [ ] **Step 7: Wire body selection into `DonationScreen` (failing test first)**

Create `test/features/donation/donation_screen_body_selection_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../../support/fake_tip_jar_service.dart';
import '../../support/localized_test_app.dart';

void main() {
  testWidgets('tipJarMode true renders tip buttons, not Ko-fi', (tester) async {
    final fake = FakeTipJarService();
    await tester.pumpWidget(localizedTestApp(
      home: DonationScreen(
        tipJarMode: true,
        createTipJar: () => fake,
        kofiUrl: 'https://ko-fi.com/x',
        bitcoinAddress: 'bc1qexample',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tip-button-tip_small')), findsOneWidget);
    expect(find.byKey(const Key('donation-kofi-button')), findsNothing);
    fake.dispose();
  });

  testWidgets('tipJarMode false renders Ko-fi/BTC, not tips', (tester) async {
    await tester.pumpWidget(localizedTestApp(
      home: const DonationScreen(
        tipJarMode: false,
        kofiUrl: 'https://ko-fi.com/x',
        bitcoinAddress: 'bc1qexample',
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
    expect(find.byKey(const Key('tip-button-tip_small')), findsNothing);
  });
}
```

Run: `flutter test test/features/donation/donation_screen_body_selection_test.dart`
Expected: FAIL — `tipJarMode`/`createTipJar` params don't exist yet.

- [ ] **Step 8: Modify `DonationScreen`**

In `lib/features/donation/donation_screen.dart`:

1. Add imports:
```dart
import 'donation_availability.dart';
import 'tip_jar/storekit_tip_jar_service.dart';
import 'tip_jar/tip_jar_body.dart';
import 'tip_jar/tip_jar_service.dart';
```

2. Add a default factory near the top-level helpers:
```dart
TipJarService _defaultTipJar() => StoreKitTipJarService();
```

3. Add constructor params + fields (keep existing ones):
```dart
  const DonationScreen({
    super.key,
    this.kofiUrl = DonationConfig.kofiUrl,
    this.bitcoinAddress = DonationConfig.bitcoinAddress,
    this.openUrl = _launchExternal,
    this.copyToClipboard = _writeClipboard,
    this.createTipJar = _defaultTipJar,
    this.tipJarMode,
  });

  final String kofiUrl;
  final String bitcoinAddress;
  final DonationUrlOpener openUrl;
  final DonationClipboardWriter copyToClipboard;

  /// Builds the tip-jar service (iOS). Injectable for tests.
  final TipJarService Function() createTipJar;

  /// Force tip-jar (`true`) or Ko-fi/BTC (`false`) body. `null` → platform
  /// default (`tipJarAvailable`). Tests pass an explicit value.
  final bool? tipJarMode;
```

4. Update `route()`:
```dart
  static Route<void> route({
    TipJarService Function()? createTipJar,
    bool? tipJarMode,
  }) => MaterialPageRoute<void>(
    builder: (_) => DonationScreen(
      createTipJar: createTipJar ?? _defaultTipJar,
      tipJarMode: tipJarMode,
    ),
  );
```

5. In `build`, choose the body. Extract the current `ListView(...children:[...])` into a private `_kofiBtcBody(context)` method (verbatim move of the existing children). Then:
```dart
  @override
  Widget build(BuildContext context) {
    final r = context.ream;
    final showTips = tipJarMode ?? tipJarAvailable;
    return Scaffold(
      backgroundColor: r.paper,
      appBar: ReamBackHeader(
        title: context.l10n.settingsSupportApp,
        onBack: () => Navigator.of(context).maybePop(),
      ),
      body: showTips
          ? ListView(
              padding: const EdgeInsets.all(20),
              children: [
                ..._headerChildren(context), // icon + headline + disclaimer + note
                const SizedBox(height: 18),
                TipJarBody(createService: createTipJar),
              ],
            )
          : _kofiBtcBody(context),
    );
  }
```
Factor the shared header (favorite icon, `donationHeadline`, `donationDisclaimer`, `donationOptionalNote` container) into `_headerChildren(BuildContext)` so both bodies reuse it (DRY). The Ko-fi/BTC body keeps its existing `if (kofiUrl.isNotEmpty)` / `if (bitcoinAddress.isNotEmpty)` sections after the shared header.

- [ ] **Step 9: Run both widget test files to green + analyze**

Run: `flutter test test/features/donation/tip_jar_body_test.dart test/features/donation/donation_screen_body_selection_test.dart && flutter analyze`
Expected: PASS, zero issues.

- [ ] **Step 10: Add the BDD `.feature` + steps**

Create `test/features/donation/tip_jar.feature`:

```gherkin
Feature: iOS tip jar
  Scenario: Successful tip shows a thank-you
    Given the tip jar has products
    When I tap the small tip
    Then I see the tip thank-you dialog

  Scenario: Store unavailable
    Given the tip jar has no products
    Then I see the tip unavailable message
```

Add step implementations under `test/step/` (shared per `build.yaml`). Each generated step name maps to a `test/step/<snake>.dart`. Implement them to pump `DonationScreen(tipJarMode: true, createTipJar: () => fake)` with a `FakeTipJarService` held in the `World`/context per the existing step pattern (mirror an existing feature's step + world setup, e.g. the feedback or donation-banner steps). Provide:
- `the_tip_jar_has_products.dart` — construct `FakeTipJarService()` with default products, pump the screen.
- `the_tip_jar_has_no_products.dart` — `FakeTipJarService()..scriptProducts(const [])`, pump.
- `i_tap_the_small_tip.dart` — `tester.tap(find.byKey(const Key('tip-button-tip_small')))`.
- `i_see_the_tip_thank_you_dialog.dart` — `expect(find.byKey(const Key('tip-thank-you-dialog')), findsOneWidget)`.
- `i_see_the_tip_unavailable_message.dart` — `expect(find.byKey(const Key('tip-unavailable')), findsOneWidget)`.

Regenerate:
```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 11: Run the generated BDD test**

Run: `flutter test test/features/donation/tip_jar_test.dart`
Expected: PASS.

- [ ] **Step 12: Commit**

```bash
dart format lib test
git add lib/l10n lib/features/donation test/features/donation test/step
git commit -m "feat(donation): iOS tip-jar UI, l10n, and BDD"
```

---

## Task 5: Production wiring + full host suite

**Files:**
- Test: `test/l10n/app_wiring_test.dart` (extend) or new `test/features/donation/donation_wiring_test.dart`

**Interfaces:**
- Consumes everything above. No new production code beyond confirming `DonationScreen.route()` (no-arg) is what the banner + Settings call and that it defaults to `StoreKitTipJarService` on iOS and never constructs it on Android (tip-jar body is not built when `tipJarMode`/`tipJarAvailable` is false).

- [ ] **Step 1: Write a wiring test**

Create `test/features/donation/donation_wiring_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

import '../../support/localized_test_app.dart';

void main() {
  testWidgets('Android body is Ko-fi/BTC and builds no tip jar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(localizedTestApp(
        home: const DonationScreen(
          kofiUrl: 'https://ko-fi.com/x',
          bitcoinAddress: 'bc1qexample',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
      expect(find.byKey(const Key('tip-button-tip_small')), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
```

- [ ] **Step 2: Run it**

Run: `flutter test test/features/donation/donation_wiring_test.dart`
Expected: PASS (default `createTipJar` is never invoked on Android because `TipJarBody` isn't built — so no StoreKit platform channel is touched on host).

- [ ] **Step 3: Run the FULL host suite (catches cross-file regressions)**

Run: `flutter test`
Expected: PASS. Investigate any failure before proceeding — a per-file green can hide cross-file breakage (this repo has been bitten by that).

- [ ] **Step 4: analyze + format + commit**

```bash
flutter analyze
dart format lib test
git add test/features/donation/donation_wiring_test.dart
git commit -m "test(donation): tip-jar production wiring + Android-body regression guard"
```

---

## Task 6: Device verification (gated on human prerequisites)

**Files:**
- Create: `integration_test/tip_jar_device_test.dart`

**Human prerequisites (record as an explicit named gap until each is satisfied — never silent):**
1. Three consumable IAP products `tip_small`/`tip_medium`/`tip_large` created in App Store Connect with metadata + price points, submitted **with a build**.
2. Paid Applications agreement **active** (else `queryProductDetails` returns zero products).
3. A **sandbox tester** Apple ID signed into the test iPhone (Settings → App Store → Sandbox Account).

**Interfaces:**
- Consumes the real `StoreKitTipJarService`.

- [ ] **Step 1: Write the device test**

Create `integration_test/tip_jar_device_test.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/donation/tip_jar/storekit_tip_jar_service.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('iOS: StoreKit resolves the three tip products', (tester) async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return; // Android has no tip jar; this test is iOS-only.
    }
    final service = StoreKitTipJarService();
    final products = await service.loadProducts();
    service.dispose();

    expect(products.map((p) => p.id).toList(),
        ['tip_small', 'tip_medium', 'tip_large']);
    for (final p in products) {
      expect(p.price, isNotEmpty); // StoreKit-localized price string
    }
  });
}
```

- [ ] **Step 2: Run on a physical iPhone (sandbox)**

Run: `flutter test integration_test/tip_jar_device_test.dart -d <ios-device-id>`
Expected: PASS — the three products resolve with non-empty localized prices. If it returns zero products, a human prerequisite is unmet (agreement inactive, products not yet approved, or sandbox account missing) — record it as the named gap, do not claim done.

- [ ] **Step 3: Manual sandbox purchase smoke test (real StoreKit sheet)**

Run the app on the iPhone: `flutter run -d <ios-device-id>` → open Settings → "Support the app" → tap the smallest tip → complete the sandbox purchase → confirm the thank-you dialog → tap the tip again to confirm the consumable is repurchasable. Record the result.

- [ ] **Step 4: Android confirms the tip jar stays hidden**

Run: `flutter run -d <android-device-id>` → open Settings → "Support the app" → confirm Ko-fi + Bitcoin show and no tip buttons appear.

- [ ] **Step 5: Commit + record evidence**

```bash
git add integration_test/tip_jar_device_test.dart
git commit -m "test(donation): on-device StoreKit tip-jar verification"
```
Paste the device run output. If prerequisites 1–3 are unmet, state the exact gap and platform explicitly.

---

## Self-Review (author checklist — completed)

**Spec coverage:** platform split → T1; products/IDs → T2; StoreKit service + consumable completion → T3; tip-jar UI states + thank-you dialog + unavailable/error + l10n → T4; wiring/DI default → T4 (screen seam) + T5; both-platform device proof + human prereqs as named gap → T6. External-Apple-Pay rejection is documented in the spec (no code). ✔

**Placeholder scan:** every code step has full code; l10n step gives all 6 keys × 11 locales verbatim; no "TBD"/"handle errors"/"similar to". ✔

**Type consistency:** `TipJarService`/`TipProduct`/`TipEvent*`/`kTipProductIds`/`tipEventFromStatus`/`TipJarBody({createService})`/`DonationScreen({createTipJar, tipJarMode})` used identically across T2→T6. `FakeTipJarService.scriptProducts/scriptNextBuy/scriptLoadThrows` match the fake definition. ✔

**Known confirmations for the implementer (not blockers):** the `package:mobile/...` import prefix, the `localizedTestApp` helper name/signature, and `ReamActionButton`'s `onPressed` nullability should each be confirmed against an existing file the first time they're used, and matched — the plan notes these inline.
