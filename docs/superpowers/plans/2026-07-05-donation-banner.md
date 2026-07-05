# Donation Banner + Screen Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible donation banner to the home and saved-file viewer screens that opens a store-compliant donation screen (Ko-fi via external browser + Bitcoin QR/copy).

**Architecture:** A new `lib/features/donation/` feature with three files: a config holding swap-later constants, a `DonationScreen`, and a `DonationBanner` widget placed in each Scaffold's `bottomNavigationBar` slot. Ko-fi opens in the external browser; Bitcoin is display-only (QR + copyable address). Both sections and the whole banner degrade gracefully when config values are empty.

**Tech Stack:** Flutter 3.44.4 (Material 3), `url_launcher: ^6.3.2`, `qr_flutter: ^4.1.0`, `flutter_test`.

## Global Constraints

- **Store safety (keystone):** Ko-fi MUST open in the external browser via `url_launcher` with `LaunchMode.externalApplication` — never an in-app webview. Bitcoin is display-only. The donation screen MUST show a disclaimer that the user receives **no features, benefits, or content** in return. No In-App Purchase / Play Billing.
- **Config is the single source of truth:** all donation values live in `DonationConfig`. No Ko-fi URL or BTC address hardcoded anywhere else. Empty string means "not configured" → corresponding UI is hidden.
- **Banner is fixed:** always visible, non-dismissible, on both home and viewer screens.
- **Feature directory:** `lib/features/donation/`. Tests under `test/features/donation/`.
- **Flutter version:** 3.44.4 stable. Material 3 (`useMaterial3: true`, `colorSchemeSeed: Colors.indigo`).

---

### Task 1: Dependencies + config constants

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (add `url_launcher: ^6.3.2`, `qr_flutter: ^4.1.0` under `dependencies:`)
- Create: `apps/mobile/lib/features/donation/donation_config.dart`
- Test: `apps/mobile/test/features/donation/donation_config_test.dart`

**Interfaces:**
- Produces: `class DonationConfig` with `static const String kofiUrl` and `static const String bitcoinAddress` (both default `''`).

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/donation/donation_config_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_config.dart';

void main() {
  test('exposes kofiUrl and bitcoinAddress as strings', () {
    expect(DonationConfig.kofiUrl, isA<String>());
    expect(DonationConfig.bitcoinAddress, isA<String>());
  });

  test('defaults are empty (unconfigured) so no dead links ship', () {
    expect(DonationConfig.kofiUrl, '');
    expect(DonationConfig.bitcoinAddress, '');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/donation/donation_config_test.dart`
Expected: FAIL — `Target of URI doesn't exist: 'package:mobile/features/donation/donation_config.dart'`.

- [ ] **Step 3: Add dependencies**

In `apps/mobile/pubspec.yaml`, under `dependencies:` (e.g. after `syncfusion_flutter_pdf:`), add:

```yaml
  url_launcher: ^6.3.2
  qr_flutter: ^4.1.0
```

Then run: `cd apps/mobile && flutter pub get`
Expected: resolves successfully.

- [ ] **Step 4: Create the config file**

Create `apps/mobile/lib/features/donation/donation_config.dart`:

```dart
/// Swap-later constants for the donation feature. Fill these in when the
/// Ko-fi page and Bitcoin wallet exist. An empty string means "not configured
/// yet" — the UI hides the corresponding section so no dead link ever ships.
///
/// These are the ONLY place donation values live. Do not hardcode a Ko-fi URL
/// or BTC address anywhere else.
class DonationConfig {
  const DonationConfig._();

  // TODO: set your Ko-fi page, e.g. 'https://ko-fi.com/yourname'.
  static const String kofiUrl = '';

  // TODO: set your Bitcoin address, e.g. 'bc1q...'.
  static const String bitcoinAddress = '';
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/donation/donation_config_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/features/donation/donation_config.dart apps/mobile/test/features/donation/donation_config_test.dart
git commit -m "feat(donation): add url_launcher/qr_flutter deps and config constants"
```

---

### Task 2: DonationScreen

**Files:**
- Create: `apps/mobile/lib/features/donation/donation_screen.dart`
- Test: `apps/mobile/test/features/donation/donation_screen_test.dart`

**Interfaces:**
- Consumes: `DonationConfig.kofiUrl`, `DonationConfig.bitcoinAddress` (Task 1).
- Produces: `class DonationScreen extends StatelessWidget` with constructor
  `const DonationScreen({super.key, this.kofiUrl = DonationConfig.kofiUrl, this.bitcoinAddress = DonationConfig.bitcoinAddress})` and fields `final String kofiUrl; final String bitcoinAddress;`. Injectable params (defaulting to config) exist purely so tests can exercise configured/empty states without mutating global const.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/donation/donation_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester,
      {required String kofiUrl, required String bitcoinAddress}) async {
    await tester.pumpWidget(MaterialApp(
      home: DonationScreen(kofiUrl: kofiUrl, bitcoinAddress: bitcoinAddress),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('always shows the no-benefits disclaimer', (tester) async {
    await pump(tester, kofiUrl: '', bitcoinAddress: '');
    expect(
      find.textContaining('no features, benefits, or content'),
      findsOneWidget,
    );
  });

  testWidgets('hides Ko-fi and Bitcoin sections when unconfigured',
      (tester) async {
    await pump(tester, kofiUrl: '', bitcoinAddress: '');
    expect(find.byKey(const Key('donation-kofi-button')), findsNothing);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsNothing);
  });

  testWidgets('shows Ko-fi button and Bitcoin section when configured',
      (tester) async {
    await pump(tester,
        kofiUrl: 'https://ko-fi.com/example',
        bitcoinAddress: 'bc1qexampleaddress');
    expect(find.byKey(const Key('donation-kofi-button')), findsOneWidget);
    expect(find.byKey(const Key('donation-bitcoin-section')), findsOneWidget);
    expect(find.text('bc1qexampleaddress'), findsOneWidget);
  });

  testWidgets('copy button writes the Bitcoin address to the clipboard',
      (tester) async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform,
        (MethodCall call) async {
      calls.add(call);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await pump(tester,
        kofiUrl: '', bitcoinAddress: 'bc1qexampleaddress');
    await tester.tap(find.byKey(const Key('donation-bitcoin-copy')));
    await tester.pumpAndSettle();

    final setData = calls.firstWhere((c) => c.method == 'Clipboard.setData');
    expect((setData.arguments as Map)['text'], 'bc1qexampleaddress');
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/donation/donation_screen_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '...donation_screen.dart'`.

- [ ] **Step 3: Write the implementation**

Create `apps/mobile/lib/features/donation/donation_screen.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'donation_config.dart';

/// Full-screen donation page. Ko-fi opens in the external browser (store-safe:
/// no in-app payment collection); Bitcoin is display-only (QR + copyable
/// address). Sections hide when their config value is empty. A prominent
/// disclaimer states donations grant no benefits.
class DonationScreen extends StatelessWidget {
  const DonationScreen({
    super.key,
    this.kofiUrl = DonationConfig.kofiUrl,
    this.bitcoinAddress = DonationConfig.bitcoinAddress,
  });

  final String kofiUrl;
  final String bitcoinAddress;

  Future<void> _openKofi() async {
    final uri = Uri.tryParse(kofiUrl);
    if (uri == null) return;
    // externalApplication keeps payment outside the app (App Store 3.1.1).
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  Future<void> _copyAddress(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: bitcoinAddress));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bitcoin address copied')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Support the app')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Icon(Icons.favorite, color: Colors.amber.shade700, size: 48),
          const SizedBox(height: 16),
          Text(
            'Thank you for considering a donation!',
            style: theme.textTheme.titleLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          Text(
            'This is a voluntary donation only. You receive no features, '
            'benefits, or content in return — it simply helps support ongoing '
            'development.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          if (kofiUrl.isNotEmpty) ...[
            FilledButton.icon(
              key: const Key('donation-kofi-button'),
              onPressed: _openKofi,
              icon: const Icon(Icons.local_cafe_outlined),
              label: const Text('Donate via Ko-fi'),
            ),
            const SizedBox(height: 24),
          ],
          if (bitcoinAddress.isNotEmpty)
            _BitcoinSection(
              key: const Key('donation-bitcoin-section'),
              address: bitcoinAddress,
              onCopy: () => _copyAddress(context),
            ),
        ],
      ),
    );
  }
}

class _BitcoinSection extends StatelessWidget {
  const _BitcoinSection({
    super.key,
    required this.address,
    required this.onCopy,
  });

  final String address;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text('Or donate with Bitcoin', style: theme.textTheme.titleMedium),
        const SizedBox(height: 16),
        Container(
          color: Colors.white,
          padding: const EdgeInsets.all(12),
          child: QrImageView(
            data: address,
            version: QrVersions.auto,
            size: 200,
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(
          address,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          key: const Key('donation-bitcoin-copy'),
          onPressed: onCopy,
          icon: const Icon(Icons.copy),
          label: const Text('Copy address'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/donation/donation_screen_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/donation/donation_screen.dart apps/mobile/test/features/donation/donation_screen_test.dart
git commit -m "feat(donation): add DonationScreen with Ko-fi and Bitcoin sections"
```

---

### Task 3: DonationBanner

**Files:**
- Create: `apps/mobile/lib/features/donation/donation_banner.dart`
- Test: `apps/mobile/test/features/donation/donation_banner_test.dart`

**Interfaces:**
- Consumes: `DonationScreen` (Task 2).
- Produces: `class DonationBanner extends StatelessWidget` with `const DonationBanner({super.key})`. On tap, pushes `MaterialPageRoute(builder: (_) => const DonationScreen())`.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/donation/donation_banner_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/donation/donation_screen.dart';

void main() {
  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox.shrink(),
        bottomNavigationBar: DonationBanner(),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('renders a support message', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('donation-banner')), findsOneWidget);
    expect(find.textContaining('support'), findsOneWidget);
  });

  testWidgets('tapping the banner opens the donation screen', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const Key('donation-banner')));
    await tester.pumpAndSettle();
    expect(find.byType(DonationScreen), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/donation/donation_banner_test.dart`
Expected: FAIL — `Target of URI doesn't exist: '...donation_banner.dart'`.

- [ ] **Step 3: Write the implementation**

Create `apps/mobile/lib/features/donation/donation_banner.dart`:

```dart
import 'package:flutter/material.dart';

import 'donation_screen.dart';

/// A fixed, always-visible banner inviting the user to donate. Placed in a
/// Scaffold's bottomNavigationBar slot so it never scrolls over or overlaps
/// content. The whole banner is a single tap target that opens [DonationScreen].
class DonationBanner extends StatelessWidget {
  const DonationBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final amber = Colors.amber.shade700;
    return Material(
      color: Colors.amber.shade50,
      child: SafeArea(
        top: false,
        child: InkWell(
          key: const Key('donation-banner'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const DonationScreen()),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Icon(Icons.local_cafe_outlined, color: amber),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Enjoying the app? Tap to support it — thank you!'),
                ),
                Icon(Icons.chevron_right, color: amber),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/donation/donation_banner_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/donation/donation_banner.dart apps/mobile/test/features/donation/donation_banner_test.dart
git commit -m "feat(donation): add tappable DonationBanner widget"
```

---

### Task 4: Wire the banner into the home and viewer screens

**Files:**
- Modify: `apps/mobile/lib/features/library/home_screen.dart` (add import + `bottomNavigationBar` to the Scaffold at line ~197)
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart` (add import + `bottomNavigationBar` to the Scaffold at line ~471)
- Test: `apps/mobile/test/features/donation/donation_banner_wiring_test.dart`

**Interfaces:**
- Consumes: `DonationBanner` (Task 3), existing `HomeScreen` / `PageViewerScreen` constructors and the `fakeLibraryDependencies` / `grantedScanDependencies` / `FakeDocumentRepository` test helpers in `test/support/`.
- Produces: nothing new (integration only).

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/donation/donation_banner_wiring_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/donation/donation_banner.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

class _OnePageRepo extends FakeDocumentRepository {
  @override
  Future<List<PageImage>> getDocumentPages(int documentId) async =>
      [PageImage(position: 1, imagePath: '/nonexistent/p.jpg')];
}

void main() {
  testWidgets('home screen shows the donation banner', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(FakeDocumentRepository()),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DonationBanner), findsOneWidget);
  });

  testWidgets('page viewer shows the donation banner', (tester) async {
    final DocumentRepository repo = _OnePageRepo();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Scan X', repository: repo),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(DonationBanner), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/donation/donation_banner_wiring_test.dart`
Expected: FAIL — `find.byType(DonationBanner)` finds zero widgets on both screens.

- [ ] **Step 3: Wire into the home screen**

In `apps/mobile/lib/features/library/home_screen.dart`, add to the import block (after the existing feature imports, e.g. after `import 'widgets/sort_control_bar.dart';`):

```dart
import '../donation/donation_banner.dart';
```

Then in the `build` method's `Scaffold` (currently ends after `floatingActionButton:` at ~line 212), add a `bottomNavigationBar`:

```dart
    return Scaffold(
      appBar: _searching ? _buildSearchAppBar() : _buildNormalAppBar(),
      body: _loading
          ? const Center(
              key: Key('documents-loading'),
              child: CircularProgressIndicator())
          : _error
              ? _buildError()
              : _buildBody(),
      floatingActionButton: _searching
          ? null
          : FloatingActionButton.extended(
              onPressed: _repository == null ? null : _openScan,
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan'),
            ),
      bottomNavigationBar: const DonationBanner(),
    );
```

- [ ] **Step 4: Wire into the page viewer screen**

In `apps/mobile/lib/features/library/page_viewer_screen.dart`, add to the import block (after the existing feature imports):

```dart
import '../donation/donation_banner.dart';
```

Then in the `build` method's `Scaffold` (the one whose `body:` ends with `_buildPages(_pages!)` at ~line 567), add a `bottomNavigationBar` immediately after the `body:`:

```dart
      body: _loading
          ? const Center(
              key: Key('page-viewer-loading'),
              child: CircularProgressIndicator())
          : _error
              ? _buildError()
              : (_pages == null || _pages!.isEmpty)
                  ? _buildEmpty()
                  : _buildPages(_pages!),
      bottomNavigationBar: const DonationBanner(),
    );
```

- [ ] **Step 5: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/donation/donation_banner_wiring_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Run the full donation suite + analyzer**

Run: `cd apps/mobile && flutter test test/features/donation/ && flutter analyze lib/features/donation`
Expected: all donation tests PASS; analyzer reports no issues for the donation feature.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/home_screen.dart apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/features/donation/donation_banner_wiring_test.dart
git commit -m "feat(donation): show donation banner on home and viewer screens"
```

---

## Notes for the implementer

- **Do not fill in real Ko-fi / BTC values.** They stay empty in `DonationConfig` until the user provides them. The UI is designed to hide unconfigured sections, so an empty config is a valid shipping state (banner still shows and opens a screen with only the disclaimer).
- **Device verification (post-merge, by the user):** once real config values are set, verify on-device that (a) the banner appears fixed at the bottom of both screens without covering the Scan FAB or the viewer thumbnail strip, (b) the Ko-fi button opens the system browser, and (c) the copy button copies the address. Host tests cannot exercise `url_launcher`'s real platform channel.
- **Android:** `url_launcher` opening `https://` needs no extra manifest queries. If a future non-http scheme is added, revisit `<queries>` in `AndroidManifest.xml`.
```
