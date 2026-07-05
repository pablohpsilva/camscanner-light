# Sharing Leftovers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the deferred Feature 12 share channels (link-share + fax) as a clean seam plus honest UX — two new interfaces with Unavailable default impls, and a DRY share menu surfacing both actions as "not available yet" across all four share points.

**Architecture:** Two new interfaces (`FaxProvider`, `LinkShareChannel`) with `Unavailable*` default impls (OCP; `ShareChannel` untouched). A shared menu module (`share_menu_button.dart`) exposes `shareExtraMenuItems(...)` + `handleShareExtra(...)` (the reusable Link/Fax entries + the not-available SnackBar) and a standalone `ShareMenuButton`. pdf_preview + recognized_text swap their share IconButton for `ShareMenuButton`; page_viewer + library add the shared entries to their existing menus. The interfaces are injected in `library_dependencies` as the future seam (unit-tested); the shipped UI shows the SnackBar and builds no available branch.

**Tech Stack:** Flutter/Dart, `flutter_test` (widget), `bdd_widget_test` (on-device BDD), bash verify harness (`scripts/verify/lib.sh`).

## Global Constraints

- **This release ships the not-available behavior only.** Tapping Fax/Share-link shows the shared SnackBar and calls no channel. The available branch (real fax-number entry, real link-then-share) is **out of scope** — do not build it. `isAvailable` lives on the interfaces as the tested seam, not a UI branch (no dead available-path).
- **`ShareChannel` is untouched** (OCP). Link-share is a **separate** `LinkShareChannel` (it returns a `Uri`, which doesn't fit `share(List<String>) → void`).
- **No new off-device egress.** The Unavailable impls send nothing; files stay the already-scrubbed Feature 07 exports.
- **Existing share/export/print behavior is preserved** on every screen — only the share *affordance* changes (IconButton → menu) or gains items.
- **Shared copy (verbatim):** `kLinkShareUnavailableMessage = "Link sharing isn't available yet"`, `kFaxUnavailableMessage = "Fax isn't available yet"`. Menu values: `share-link`, `fax`.
- **Fax is omitted on the recognized-text (.txt) screen** (`showFax: false`) — you fax documents/images, not raw text.
- TDD / SOLID / KISS / DRY; single-responsibility files; frequent commits.
- Spec: `docs/superpowers/specs/2026-07-05-sharing-leftovers-design.md`.
- Run all Flutter commands from `apps/mobile`.

---

### Task 1: `FaxProvider` interface + `UnavailableFaxProvider`

**Files:**
- Create: `apps/mobile/lib/features/library/fax_provider.dart`
- Test: `apps/mobile/test/features/library/fax_provider_test.dart`

**Interfaces:**
- Produces: `abstract interface class FaxProvider { bool get isAvailable; Future<void> sendFax({required List<String> filePaths, required String faxNumber}); }` and `class UnavailableFaxProvider implements FaxProvider` (const, `isAvailable => false`, `sendFax` throws `UnsupportedError`). Consumed by Task 6 (wiring).

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/fax_provider_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/fax_provider.dart';

void main() {
  group('UnavailableFaxProvider', () {
    const provider = UnavailableFaxProvider();

    test('is not available', () {
      expect(provider.isAvailable, isFalse);
    });

    test('sendFax throws UnsupportedError', () {
      expect(
        () => provider.sendFax(filePaths: const ['/tmp/a.pdf'], faxNumber: '123'),
        throwsUnsupportedError,
      );
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/fax_provider_test.dart`
Expected: FAIL — `fax_provider.dart` / `FaxProvider` not found.

- [ ] **Step 3: Implement `fax_provider.dart`**

Create `apps/mobile/lib/features/library/fax_provider.dart`:

```dart
/// Sends documents to a fax number via a third-party fax provider. The OCP
/// extension point for Feature 12's deferred fax channel: a real provider is a
/// new implementation; existing callers are undisturbed.
///
/// No provider is wired today (fax needs a paid off-device service), so the
/// default [UnavailableFaxProvider] reports [isAvailable] == false and the UI
/// surfaces fax as "not available yet".
abstract interface class FaxProvider {
  /// Whether faxing is currently backed by a real provider. False by default.
  bool get isAvailable;

  /// Faxes the already-scrubbed [filePaths] to [faxNumber]. Callers must gate on
  /// [isAvailable]; the default impl throws [UnsupportedError].
  Future<void> sendFax({
    required List<String> filePaths,
    required String faxNumber,
  });
}

/// Default "no provider configured" implementation.
class UnavailableFaxProvider implements FaxProvider {
  const UnavailableFaxProvider();

  @override
  bool get isAvailable => false;

  @override
  Future<void> sendFax({
    required List<String> filePaths,
    required String faxNumber,
  }) =>
      throw UnsupportedError('Fax is not available (no provider configured).');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/fax_provider_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze + commit**

Run: `cd apps/mobile && flutter analyze lib/features/library/fax_provider.dart test/features/library/fax_provider_test.dart`
Expected: "No issues found!"

```bash
git add apps/mobile/lib/features/library/fax_provider.dart apps/mobile/test/features/library/fax_provider_test.dart
git commit -m "feat(share): FaxProvider interface + UnavailableFaxProvider default"
```

---

### Task 2: `LinkShareChannel` interface + `UnavailableLinkShareChannel`

**Files:**
- Create: `apps/mobile/lib/features/library/link_share_channel.dart`
- Test: `apps/mobile/test/features/library/link_share_channel_test.dart`

**Interfaces:**
- Produces: `abstract interface class LinkShareChannel { bool get isAvailable; Future<Uri> createLink(String filePath); }` and `class UnavailableLinkShareChannel implements LinkShareChannel` (const, `isAvailable => false`, `createLink` throws `UnsupportedError`). Consumed by Task 6.

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/link_share_channel_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/link_share_channel.dart';

void main() {
  group('UnavailableLinkShareChannel', () {
    const channel = UnavailableLinkShareChannel();

    test('is not available', () {
      expect(channel.isAvailable, isFalse);
    });

    test('createLink throws UnsupportedError', () {
      expect(() => channel.createLink('/tmp/a.pdf'), throwsUnsupportedError);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/link_share_channel_test.dart`
Expected: FAIL — `link_share_channel.dart` not found.

- [ ] **Step 3: Implement `link_share_channel.dart`**

Create `apps/mobile/lib/features/library/link_share_channel.dart`:

```dart
/// Produces a shareable URL for a file by uploading it to a backend. The OCP
/// extension point for Feature 12's deferred link-share channel.
///
/// Deliberately separate from [ShareChannel] (which shares files to the OS
/// sheet and returns void): link-share returns a [Uri], which does not fit that
/// signature. No backend is wired today (link-share depends on the deferred
/// Feature 11 server), so the default [UnavailableLinkShareChannel] reports
/// [isAvailable] == false and the UI surfaces link-share as "not available yet".
abstract interface class LinkShareChannel {
  /// Whether link-sharing is currently backed by a real backend. False by default.
  bool get isAvailable;

  /// Uploads [filePath] and returns a shareable URL. Callers must gate on
  /// [isAvailable]; the default impl throws [UnsupportedError].
  Future<Uri> createLink(String filePath);
}

/// Default "no backend configured" implementation.
class UnavailableLinkShareChannel implements LinkShareChannel {
  const UnavailableLinkShareChannel();

  @override
  bool get isAvailable => false;

  @override
  Future<Uri> createLink(String filePath) =>
      throw UnsupportedError('Link sharing is not available (no backend configured).');
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/link_share_channel_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 5: Analyze + commit**

Run: `cd apps/mobile && flutter analyze lib/features/library/link_share_channel.dart test/features/library/link_share_channel_test.dart`
Expected: "No issues found!"

```bash
git add apps/mobile/lib/features/library/link_share_channel.dart apps/mobile/test/features/library/link_share_channel_test.dart
git commit -m "feat(share): LinkShareChannel interface + UnavailableLinkShareChannel default"
```

---

### Task 3: Shared menu module — items, handler, `ShareMenuButton`

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/share_menu_button.dart`
- Test: `apps/mobile/test/features/library/widgets/share_menu_button_test.dart`

**Interfaces:**
- Produces (all consumed by Tasks 4 & 5):
  - `const String kLinkShareUnavailableMessage`, `kFaxUnavailableMessage`
  - `const String kShareLinkValue = 'share-link'`, `kFaxValue = 'fax'`
  - `List<PopupMenuEntry<String>> shareExtraMenuItems({required bool showFax, required String keyPrefix})`
  - `void handleShareExtra(BuildContext context, String value)`
  - `class ShareMenuButton extends StatelessWidget` with `{required Key buttonKey, required VoidCallback onShare, bool showFax = true, bool enabled = true}`

- [ ] **Step 1: Write the failing test**

Create `apps/mobile/test/features/library/widgets/share_menu_button_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('shareExtraMenuItems', () {
    testWidgets('includes Share link + Fax by default with prefixed keys',
        (tester) async {
      final items = shareExtraMenuItems(showFax: true, keyPrefix: 'p');
      expect(items.length, 2);
      expect((items[0] as PopupMenuItem).value, kShareLinkValue);
      expect((items[1] as PopupMenuItem).value, kFaxValue);
      expect(items[0].key, const Key('p-share-link'));
      expect(items[1].key, const Key('p-fax'));
    });

    testWidgets('omits Fax when showFax is false', (tester) async {
      final items = shareExtraMenuItems(showFax: false, keyPrefix: 'p');
      expect(items.length, 1);
      expect((items[0] as PopupMenuItem).value, kShareLinkValue);
    });
  });

  group('ShareMenuButton', () {
    testWidgets('Share item invokes onShare', (tester) async {
      var shared = 0;
      await tester.pumpWidget(_host(ShareMenuButton(
        buttonKey: const Key('btn'),
        onShare: () => shared++,
      )));
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-menu-share')));
      await tester.pumpAndSettle();
      expect(shared, 1);
    });

    testWidgets('Fax while unavailable shows SnackBar, does not call onShare',
        (tester) async {
      var shared = 0;
      await tester.pumpWidget(_host(ShareMenuButton(
        buttonKey: const Key('btn'),
        onShare: () => shared++,
      )));
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-menu-fax')));
      await tester.pumpAndSettle();
      expect(find.text(kFaxUnavailableMessage), findsOneWidget);
      expect(shared, 0);
    });

    testWidgets('Share link while unavailable shows SnackBar', (tester) async {
      await tester.pumpWidget(_host(ShareMenuButton(
        buttonKey: const Key('btn'),
        onShare: () {},
      )));
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('share-menu-share-link')));
      await tester.pumpAndSettle();
      expect(find.text(kLinkShareUnavailableMessage), findsOneWidget);
    });

    testWidgets('showFax:false hides the Fax item', (tester) async {
      await tester.pumpWidget(_host(ShareMenuButton(
        buttonKey: const Key('btn'),
        onShare: () {},
        showFax: false,
      )));
      await tester.tap(find.byKey(const Key('btn')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('share-menu-fax')), findsNothing);
      expect(find.byKey(const Key('share-menu-share-link')), findsOneWidget);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/widgets/share_menu_button_test.dart`
Expected: FAIL — `share_menu_button.dart` not found.

- [ ] **Step 3: Implement `share_menu_button.dart`**

Create `apps/mobile/lib/features/library/widgets/share_menu_button.dart`:

```dart
import 'package:flutter/material.dart';

/// SnackBar copy shown when link-share / fax are tapped but no real provider is
/// wired yet. Shared so tests and UI assert the same strings.
const String kLinkShareUnavailableMessage = "Link sharing isn't available yet";
const String kFaxUnavailableMessage = "Fax isn't available yet";

/// Menu values for the shared "extra" share actions.
const String kShareLinkValue = 'share-link';
const String kFaxValue = 'fax';

/// The shared Share-link (+ Fax unless [showFax] is false) menu entries.
/// [keyPrefix] namespaces the item keys so multiple menus stay unique
/// (e.g. 'document-42', 'page-viewer', 'share-menu').
List<PopupMenuEntry<String>> shareExtraMenuItems({
  required bool showFax,
  required String keyPrefix,
}) =>
    [
      PopupMenuItem<String>(
        value: kShareLinkValue,
        key: Key('$keyPrefix-share-link'),
        child: const Text('Share link'),
      ),
      if (showFax)
        PopupMenuItem<String>(
          value: kFaxValue,
          key: Key('$keyPrefix-fax'),
          child: const Text('Fax'),
        ),
    ];

/// Handles a tap on a shared extra action. This release only ships the
/// not-available path: it shows the "…isn't available yet" SnackBar. When a real
/// LinkShareChannel/FaxProvider is wired, the available branch is added here
/// together with its UX (see spec non-goals).
void handleShareExtra(BuildContext context, String value) {
  final message =
      value == kFaxValue ? kFaxUnavailableMessage : kLinkShareUnavailableMessage;
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(message)));
}

/// Standalone share menu for screens whose only share affordance was an
/// IconButton (pdf_preview, recognized_text). Share delegates to [onShare]
/// (the screen's existing behavior, verbatim); Share-link/Fax show the
/// not-available SnackBar via [handleShareExtra].
class ShareMenuButton extends StatelessWidget {
  final Key buttonKey;
  final VoidCallback onShare;
  final bool showFax;
  final bool enabled;

  const ShareMenuButton({
    super.key,
    required this.buttonKey,
    required this.onShare,
    this.showFax = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        key: buttonKey,
        enabled: enabled,
        tooltip: 'Share',
        icon: const Icon(Icons.share),
        onSelected: (value) {
          if (value == 'share') {
            onShare();
          } else {
            handleShareExtra(context, value);
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem<String>(
            value: 'share',
            key: Key('share-menu-share'),
            child: Text('Share'),
          ),
          ...shareExtraMenuItems(showFax: showFax, keyPrefix: 'share-menu'),
        ],
      );
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/widgets/share_menu_button_test.dart`
Expected: PASS (6 tests).

- [ ] **Step 5: Analyze + commit**

Run: `cd apps/mobile && flutter analyze lib/features/library/widgets/share_menu_button.dart test/features/library/widgets/share_menu_button_test.dart`
Expected: "No issues found!"

```bash
git add apps/mobile/lib/features/library/widgets/share_menu_button.dart apps/mobile/test/features/library/widgets/share_menu_button_test.dart
git commit -m "feat(share): shared share-menu module (items, handler, ShareMenuButton)"
```

---

### Task 4: pdf_preview + recognized_text → `ShareMenuButton`

**Files:**
- Modify: `apps/mobile/lib/features/library/pdf_preview_screen.dart` (the share `IconButton`, ~lines 75–83)
- Modify: `apps/mobile/lib/features/library/recognized_text_screen.dart` (the share `IconButton`, ~lines 118–123)
- Modify: `apps/mobile/test/features/library/share_routing_test.dart` (the two share tests, lines ~26 and ~54)

**Interfaces:**
- Consumes: `ShareMenuButton` (Task 3). The existing keys `pdf-preview-share` / `recognized-text-share` move onto the menu button (`buttonKey`) so callers keep the same handle to *open* the menu; the Share item key is `share-menu-share`.

- [ ] **Step 1: Update the existing share tests to the menu interaction (red)**

In `apps/mobile/test/features/library/share_routing_test.dart`, each test currently taps the share key and expects the channel invoked. Insert the menu-open + Share-item tap. Replace the pdf-preview tap line:

```dart
    await tester.tap(find.byKey(const Key('pdf-preview-share')));
```
with:
```dart
    await tester.tap(find.byKey(const Key('pdf-preview-share'))); // opens the menu
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-menu-share')));
```
And the recognized-text tap line:
```dart
    await tester.tap(find.byKey(const Key('recognized-text-share')));
```
with:
```dart
    await tester.tap(find.byKey(const Key('recognized-text-share'))); // opens the menu
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('share-menu-share')));
```
Add `import 'package:mobile/features/library/widgets/share_menu_button.dart';` if the file needs the key constants (it uses raw key strings above, so no import needed).

- [ ] **Step 2: Run to verify the tests fail**

Run: `cd apps/mobile && flutter test test/features/library/share_routing_test.dart`
Expected: FAIL — `share-menu-share` not found (still an IconButton).

- [ ] **Step 3: Swap pdf_preview's IconButton for `ShareMenuButton`**

In `apps/mobile/lib/features/library/pdf_preview_screen.dart`, add the import near the other library imports:
```dart
import 'widgets/share_menu_button.dart';
```
Replace the share `IconButton` (the block starting `IconButton(` with `key: const Key('pdf-preview-share')`) with:
```dart
          ShareMenuButton(
            buttonKey: const Key('pdf-preview-share'),
            onShare: () => unawaited(
              widget.share.share([widget.pdfPath], subject: widget.name),
            ),
          ),
```
(`unawaited` is already imported in this file.)

- [ ] **Step 4: Swap recognized_text's IconButton for `ShareMenuButton`**

In `apps/mobile/lib/features/library/recognized_text_screen.dart`, add:
```dart
import 'widgets/share_menu_button.dart';
```
Replace the share `IconButton` (`key: const Key('recognized-text-share')`, `onPressed: (_busy || !hasText) ? null : _share`) with:
```dart
          ShareMenuButton(
            buttonKey: const Key('recognized-text-share'),
            onShare: _share,
            showFax: false,
            enabled: !(_busy || !hasText),
          ),
```
If the analyzer flags `_share` (Future-returning) assigned to `VoidCallback`, wrap it: `onShare: () => unawaited(_share())` and ensure `import 'dart:async';` is present (add if missing).

- [ ] **Step 5: Run the updated tests + analyze**

Run: `cd apps/mobile && flutter test test/features/library/share_routing_test.dart`
Expected: PASS (both tests — share still routes through the channel via the menu).

Run: `cd apps/mobile && flutter analyze lib/features/library/pdf_preview_screen.dart lib/features/library/recognized_text_screen.dart`
Expected: "No issues found!"

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/pdf_preview_screen.dart apps/mobile/lib/features/library/recognized_text_screen.dart apps/mobile/test/features/library/share_routing_test.dart
git commit -m "feat(share): pdf_preview + recognized_text use ShareMenuButton (link/fax not-available)"
```

---

### Task 5: Add Link/Fax entries to page_viewer + library menus

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart` (the action `PopupMenuButton`, ~lines 483–498)
- Modify: `apps/mobile/lib/features/library/widgets/documents_list_view.dart` (the per-document `PopupMenuButton`, ~lines 40–61)
- Test: `apps/mobile/test/features/library/widgets/documents_list_view_share_extras_test.dart` (new)
- Test: `apps/mobile/test/features/library/page_viewer_share_extras_test.dart` (new)

**Interfaces:**
- Consumes: `shareExtraMenuItems`, `handleShareExtra`, `kFaxUnavailableMessage`, `kLinkShareUnavailableMessage` (Task 3).

- [ ] **Step 1: Write the documents-list widget test (red)**

Create `apps/mobile/test/features/library/widgets/documents_list_view_share_extras_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';
import 'package:mobile/features/library/widgets/share_menu_button.dart';

DocumentSummary _summary() => /* build a minimal DocumentSummary — mirror the
    existing documents_list_view_test.dart fixtures */ throw UnimplementedError();

void main() {
  testWidgets('per-document menu shows Fax → not available', (tester) async {
    final s = _summary();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
          summaries: [s],
          onShare: (_) {},
          onRename: (_) {},
        ),
      ),
    ));
    await tester.tap(find.byKey(Key('document-menu-${s.document.id}')));
    await tester.pumpAndSettle();
    expect(find.byKey(Key('document-${s.document.id}-share-link')), findsOneWidget);
    await tester.tap(find.byKey(Key('document-${s.document.id}-fax')));
    await tester.pumpAndSettle();
    expect(find.text(kFaxUnavailableMessage), findsOneWidget);
  });
}
```

Note: reuse the exact `DocumentSummary` construction from the existing
`test/features/library/widgets/documents_list_view_test.dart` (read that file and
copy its fixture builder into `_summary()` — do not invent fields).

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/widgets/documents_list_view_share_extras_test.dart`
Expected: FAIL — `document-<id>-fax` not found.

- [ ] **Step 3: Add the shared extras to `documents_list_view.dart`**

Add the import:
```dart
import 'share_menu_button.dart';
```
In the per-document `PopupMenuButton`, extend `onSelected` and `itemBuilder`. Change `onSelected`:
```dart
                  onSelected: (v) {
                    if (v == 'rename') onRename?.call(s);
                    if (v == 'share') onShare?.call(s);
                    if (v == kShareLinkValue || v == kFaxValue) {
                      handleShareExtra(context, v);
                    }
                  },
```
(`context` is the `itemBuilder: (context, i)` parameter of the enclosing
`ListView.builder` — in scope here.)

Append the shared items to `itemBuilder`, gated on `onShare != null` (only when the
row offers sharing), after the existing `share`/`rename` items:
```dart
                  itemBuilder: (context) => [
                    if (onShare != null)
                      PopupMenuItem<String>(
                        key: Key('document-share-${d.id}'),
                        value: 'share',
                        child: const Text('Share'),
                      ),
                    if (onShare != null)
                      ...shareExtraMenuItems(
                          showFax: true, keyPrefix: 'document-${d.id}'),
                    if (onRename != null)
                      PopupMenuItem<String>(
                        key: Key('document-rename-${d.id}'),
                        value: 'rename',
                        child: const Text('Rename'),
                      ),
                  ],
```

- [ ] **Step 4: Run the documents-list test + analyze**

Run: `cd apps/mobile && flutter test test/features/library/widgets/documents_list_view_share_extras_test.dart`
Expected: PASS.

Run: `cd apps/mobile && flutter analyze lib/features/library/widgets/documents_list_view.dart`
Expected: "No issues found!"

- [ ] **Step 5: Write the page_viewer test (red)**

Create `apps/mobile/test/features/library/page_viewer_share_extras_test.dart` mirroring
the existing `camera`/`page_viewer` test setup. Read
`test/features/library/page_viewer_*_test.dart` for the exact `PageViewerScreen`
construction + fakes, then assert: open the `page-viewer-page-menu`, tap
`page-viewer-fax`, expect `kFaxUnavailableMessage`. Skeleton:

```dart
// imports incl. share_menu_button.dart for kFaxUnavailableMessage
testWidgets('page menu shows Fax → not available', (tester) async {
  // ...pump PageViewerScreen with the same fakes the sibling tests use, wait for load...
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('page-viewer-share-link')), findsOneWidget);
  await tester.tap(find.byKey(const Key('page-viewer-fax')));
  await tester.pumpAndSettle();
  expect(find.text(kFaxUnavailableMessage), findsOneWidget);
});
```

- [ ] **Step 6: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_share_extras_test.dart`
Expected: FAIL — `page-viewer-fax` not found.

- [ ] **Step 7: Add the shared extras to `page_viewer_screen.dart`**

Add the import:
```dart
import 'widgets/share_menu_button.dart';
```
In the action `PopupMenuButton`, add the two values to `onSelected`:
```dart
              if (v == kShareLinkValue || v == kFaxValue) {
                handleShareExtra(context, v);
              }
```
And append the shared items to its `itemBuilder`. The current list is `const [...]`;
drop the `const` and spread the items at the end:
```dart
            itemBuilder: (_) => [
              // ...existing PopupMenuItem entries (view-text, rotate, … protect)…
              ...shareExtraMenuItems(showFax: true, keyPrefix: 'page-viewer'),
            ],
```
(Keep every existing item unchanged; only remove the outer `const` and add the spread.
`context` for `handleShareExtra` is the enclosing `build(BuildContext context)` of the
State — in scope.)

- [ ] **Step 8: Run the page_viewer test + full library suite + analyze**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_share_extras_test.dart`
Expected: PASS.

Run: `cd apps/mobile && flutter test test/features/library/`
Expected: PASS (existing page_viewer / documents-list / share tests still green — no behavior regression).

Run: `cd apps/mobile && flutter analyze lib/features/library/page_viewer_screen.dart`
Expected: "No issues found!"

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/lib/features/library/widgets/documents_list_view.dart apps/mobile/test/features/library/widgets/documents_list_view_share_extras_test.dart apps/mobile/test/features/library/page_viewer_share_extras_test.dart
git commit -m "feat(share): add Link/Fax entries to page_viewer + library menus (not-available)"
```

---

### Task 6: Wire providers into `library_dependencies` + BDD + verify script

**Files:**
- Modify: `apps/mobile/lib/features/library/library_dependencies.dart`
- Test: `apps/mobile/test/features/library/library_dependencies_share_test.dart` (new)
- Create: `apps/mobile/integration_test/r3_share_leftovers.feature` + generated `..._test.dart`
- Create: `apps/mobile/test/step/` step(s) as needed (see below)
- Create: `scripts/verify/r3.sh`

**Interfaces:**
- Consumes: `LinkShareChannel`/`UnavailableLinkShareChannel` (Task 2), `FaxProvider`/`UnavailableFaxProvider` (Task 1).

- [ ] **Step 1: Write the wiring unit test (red)**

Create `apps/mobile/test/features/library/library_dependencies_share_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/fax_provider.dart';
import 'package:mobile/features/library/library_dependencies.dart';
import 'package:mobile/features/library/link_share_channel.dart';

void main() {
  test('LibraryDependencies defaults link-share and fax to Unavailable impls', () {
    const deps = LibraryDependencies();
    expect(deps.linkShare, isA<UnavailableLinkShareChannel>());
    expect(deps.fax, isA<UnavailableFaxProvider>());
    expect(deps.linkShare.isAvailable, isFalse);
    expect(deps.fax.isAvailable, isFalse);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/library_dependencies_share_test.dart`
Expected: FAIL — `deps.linkShare` / `deps.fax` don't exist.

- [ ] **Step 3: Add the fields to `library_dependencies.dart`**

Add imports next to `import 'share_channel.dart';`:
```dart
import 'fax_provider.dart';
import 'link_share_channel.dart';
```
Add the two fields + constructor defaults to `LibraryDependencies`:
```dart
  final ShareChannel share;
  final LinkShareChannel linkShare;
  final FaxProvider fax;
  const LibraryDependencies({
    this.createRepository = _defaultCreateRepository,
    this.printer = const SystemDocumentPrinter(),
    this.share = const SystemShareChannel(),
    this.linkShare = const UnavailableLinkShareChannel(),
    this.fax = const UnavailableFaxProvider(),
  });
```

- [ ] **Step 4: Run the wiring test + analyze**

Run: `cd apps/mobile && flutter test test/features/library/library_dependencies_share_test.dart`
Expected: PASS.

Run: `cd apps/mobile && flutter analyze lib/features/library/library_dependencies.dart`
Expected: "No issues found!"

- [ ] **Step 5: Add the BDD scenario**

Create `apps/mobile/integration_test/r3_share_leftovers.feature`:
```gherkin
Feature: Share leftovers surface as not-yet-available

  Scenario: Fax on a document is not available yet
    Given the app is launched with one saved document
    And the app launches reading that same storage
    When I open the first document's menu
    And I tap the Fax action
    Then I see the message "Fax isn't available yet"
```
Generate the test: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`. Implement any missing step defs under `apps/mobile/test/step/` by reusing existing library BDD steps (read `integration_test/*.feature` + `test/step/` for the "saved document" + "open menu" steps already used by R1/R2/D-series; only the "tap the Fax action" + "see the message" steps may be new — model them on existing tap/see-text steps). Keep generated `*_test.dart` committed.

Note: per memory, a persistent-storage seed step must be followed by an explicit
"the app launches reading that same storage" step before any UI step (already in the
scenario above).

- [ ] **Step 6: Author `scripts/verify/r3.sh`**

Create `scripts/verify/r3.sh` (mirror `scripts/verify/r2.sh`):
```bash
#!/usr/bin/env bash
# Verify R3 (sharing leftovers: link-share + fax interfaces + not-available UX).
# Run: bash scripts/verify/r3.sh
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== R3 verification =="
require_tool flutter
require_tool git

# ---- Interfaces exist ----
assert_file_has "FaxProvider interface" \
  "apps/mobile/lib/features/library/fax_provider.dart" "abstract interface class FaxProvider"
assert_file_has "UnavailableFaxProvider default" \
  "apps/mobile/lib/features/library/fax_provider.dart" "class UnavailableFaxProvider"
assert_file_has "LinkShareChannel interface" \
  "apps/mobile/lib/features/library/link_share_channel.dart" "abstract interface class LinkShareChannel"
assert_file_has "UnavailableLinkShareChannel default" \
  "apps/mobile/lib/features/library/link_share_channel.dart" "class UnavailableLinkShareChannel"

# ---- Wired into the composition root ----
assert_file_has "library_dependencies injects linkShare" \
  "apps/mobile/lib/features/library/library_dependencies.dart" "UnavailableLinkShareChannel()"
assert_file_has "library_dependencies injects fax" \
  "apps/mobile/lib/features/library/library_dependencies.dart" "UnavailableFaxProvider()"

# ---- Shared menu module present ----
assert_file_has "shared share-menu module" \
  "apps/mobile/lib/features/library/widgets/share_menu_button.dart" "shareExtraMenuItems"

# ---- Unit + widget tests green ----
assert_cmd "share leftovers unit + widget tests pass" "All tests passed" \
  bash -c "cd apps/mobile && flutter test test/features/library/fax_provider_test.dart test/features/library/link_share_channel_test.dart test/features/library/widgets/share_menu_button_test.dart test/features/library/library_dependencies_share_test.dart 2>&1"

verify_summary
```

- [ ] **Step 7: Run the full suite + verify script**

Run: `cd apps/mobile && flutter test`
Expected: `All tests passed!` (full suite green).

Run: `chmod +x scripts/verify/r3.sh && bash scripts/verify/r3.sh; echo "exit=$?"`
Expected: `GATE: PASS`, exit 0.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/library_dependencies.dart apps/mobile/test/features/library/library_dependencies_share_test.dart apps/mobile/integration_test/r3_share_leftovers.feature apps/mobile/integration_test/r3_share_leftovers_test.dart apps/mobile/test/step scripts/verify/r3.sh
git commit -m "feat(share): wire link-share/fax providers into library_dependencies + R3 verify + BDD"
```

---

## Self-Review

**Spec coverage:**
- `FaxProvider` + `UnavailableFaxProvider` (isAvailable false, sendFax throws) → Task 1. ✓
- `LinkShareChannel` + `UnavailableLinkShareChannel` (isAvailable false, createLink throws) → Task 2. ✓
- `shareExtraMenuItems`/`handleShareExtra` (not-available SnackBar, keys, showFax) → Task 3. ✓
- `ShareMenuButton` on pdf_preview + recognized_text; system-share still works → Task 3 (widget) + Task 4. ✓
- page_viewer + library menus gain Link/Fax; existing behavior unchanged → Task 5. ✓
- library_dependencies injects Unavailable defaults; channels undisturbed → Task 6. ✓
- Full suite green + analyze clean → Task 6 Step 7 + per-task analyze. ✓
- Deferred (no available branch, no egress) → Global Constraints; enforced by "not-available only" behavior. ✓

**Placeholder scan:** The only `throw UnimplementedError()` is in a test fixture stub (`_summary()` in Task 5 Step 1) with an explicit instruction to replace it by copying the existing `documents_list_view_test.dart` fixture — flagged, not shipped. The page_viewer test (Task 5 Step 5) is a skeleton with explicit "read sibling tests for exact construction" guidance because that screen's fakes are extensive; the assertions are concrete. No TODO/TBD in shipped code.

**Type consistency:** `kShareLinkValue`/`kFaxValue` ('share-link'/'fax') and the message constants are defined in Task 3 and used verbatim in Tasks 4–6. `ShareMenuButton({buttonKey, onShare, showFax, enabled})` defined in Task 3, used in Task 4. `deps.linkShare`/`deps.fax` defined in Task 6, asserted in its test. Key prefixes: `share-menu` (widget), `document-<id>` (library), `page-viewer` (page menu) — consistent between item creation and test lookups.
