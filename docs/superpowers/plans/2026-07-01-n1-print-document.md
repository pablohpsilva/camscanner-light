# N1 — Print a document Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A "Print" action in the page viewer that sends the document's PDF to the OS print sheet, via a testable `DocumentPrinter` seam.

**Architecture:** `DocumentPrinter.printPdf(File, {name})` — production `SystemDocumentPrinter` wraps the `printing` package's `Printing.layoutPdf`; a `FakeDocumentPrinter` no-ops for tests. Injected through `LibraryDependencies.printer` → `HomeScreen` → `PageViewerScreen`. `_print()` reuses `exportPdf` then hands the file to the printer.

**Tech Stack:** Flutter/Dart, `printing` (new), `pdf`, drift, `bdd_widget_test` + `build_runner`.

## Global Constraints

- **iOS + Android**: `printing` handles both print sheets; the seam + menu are pure Dart. No per-OS branching.
- **Testable seam**: the OS print UI can't be automated — everything routes through `DocumentPrinter`; tests/BDD inject a no-op fake so nothing blocks on a native dialog.
- **Reuse** the existing `exportPdf` (searchable, metadata-scrubbed) PDF — printing is just a new destination.
- **TDD/BDD first**; SOLID/KISS/DRY.
- **Commits**: explicit file paths (never `git add -A`). Trailer: `Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>`. Do NOT commit report files.
- **Do NOT touch**: `apps/mobile/android/build.gradle.kts`, `apps/mobile/ios/Podfile.lock`, `apps/mobile/android/build/`, `.superpowers/`. (Adding `printing` to `pubspec.yaml` + `pubspec.lock` is expected and allowed; do NOT run iOS `pod install`.)
- **On-device gate**: BDD + integration tests pass on Samsung `RZCY51D0T1K`.
- Paths relative to `apps/mobile/` unless noted (`scripts/`, `docs/` are repo-root).

---

### Task 1: `DocumentPrinter` seam + "Print" action

**Files:**
- Modify: `pubspec.yaml` (add `printing`)
- Create: `lib/features/library/document_printer.dart`
- Modify: `lib/features/library/library_dependencies.dart` (add `printer`)
- Modify: `lib/features/library/home_screen.dart` (thread `printer` to the viewer)
- Modify: `lib/features/library/page_viewer_screen.dart` (`printer` param + `_print()` + menu)
- Modify: `test/support/fake_library.dart` (add `FakeDocumentPrinter`)
- Test: `test/features/library/page_viewer_print_test.dart` (create)

- [ ] **Step 1: Add the `printing` dependency**

In `pubspec.yaml`, under `dependencies:` (near `pdf:`/`pdfx:`), add:

```yaml
  printing: ^5.13.0
```

Run: `cd apps/mobile && flutter pub get`
Expected: resolves cleanly (printing 5.13.x is compatible with `pdf ^3.11`). If it fails to resolve, report the constraint conflict as BLOCKED — do not force an incompatible version.

- [ ] **Step 2: Create the seam**

Create `lib/features/library/document_printer.dart`:

```dart
import 'dart:io';

import 'package:printing/printing.dart';

/// Sends a PDF to the OS print sheet (print / save-as-PDF / AirPrint). Injectable
/// (DIP) so tests and the on-device BDD use a no-op fake instead of the native
/// print UI (which cannot be driven by an automated test).
abstract interface class DocumentPrinter {
  Future<void> printPdf(File pdf, {required String name});
}

/// Production printer backed by the `printing` package. Reads the PDF bytes and
/// hands them to the platform print sheet. Nothing leaves the device except via
/// the user's chosen printer/destination.
class SystemDocumentPrinter implements DocumentPrinter {
  const SystemDocumentPrinter();

  @override
  Future<void> printPdf(File pdf, {required String name}) async {
    await Printing.layoutPdf(
      name: name,
      onLayout: (_) async => pdf.readAsBytes(),
    );
  }
}
```

- [ ] **Step 3: Add `printer` to `LibraryDependencies`**

In `lib/features/library/library_dependencies.dart`, add the import and field:

```dart
import 'document_printer.dart';
```

In the `LibraryDependencies` class, add a field + default:

```dart
  final DocumentPrinter printer;
```
and in its `const` constructor parameter list add `this.printer = const SystemDocumentPrinter(),`.

- [ ] **Step 4: Thread the printer through `HomeScreen`**

In `lib/features/library/home_screen.dart`, where it constructs `PageViewerScreen(...)` (around line 116), add:

```dart
          printer: widget.libraryDependencies.printer,
```

- [ ] **Step 5: Add the `FakeDocumentPrinter` to test support**

In `test/support/fake_library.dart`, add (top-level, near the other fakes; add `import '../../lib/...'`? NO — use the package import already present: `package:mobile/features/library/document_printer.dart`):

```dart
/// No-op printer for tests: records the last file/name, never touches the
/// native print plugin.
class FakeDocumentPrinter implements DocumentPrinter {
  File? lastFile;
  String? lastName;
  final bool throwOnPrint;
  FakeDocumentPrinter({this.throwOnPrint = false});

  @override
  Future<void> printPdf(File pdf, {required String name}) async {
    if (throwOnPrint) throw Exception('fake: print failed');
    lastFile = pdf;
    lastName = name;
  }
}
```
Add the import at the top of `fake_library.dart`:
```dart
import 'package:mobile/features/library/document_printer.dart';
```

- [ ] **Step 6: Write the failing widget test**

Create `test/features/library/page_viewer_print_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  Future<void> tapPrint(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('page-viewer-print')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('Print sends the exported PDF to the printer', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    final printer = FakeDocumentPrinter();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 3, name: 'Report', repository: repo, printer: printer),
    ));
    await tester.pumpAndSettle();

    await tapPrint(tester);

    expect(printer.lastName, 'Report');
    expect(printer.lastFile, isNotNull);
    expect(find.text('Sent to printer'), findsOneWidget);
  });

  testWidgets('a failing export shows a print error', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnExport: true,
      pages: const [PageImage(position: 1, imagePath: '/a.jpg')],
    );
    final printer = FakeDocumentPrinter();
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(
          documentId: 3, name: 'Report', repository: repo, printer: printer),
    ));
    await tester.pumpAndSettle();

    await tapPrint(tester);

    expect(printer.lastFile, isNull);
    expect(find.text("Couldn't print"), findsOneWidget);
  });
}
```

- [ ] **Step 7: Run the test to verify it fails**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_print_test.dart`
Expected: FAIL — `PageViewerScreen` has no `printer` param / no `page-viewer-print` item.

- [ ] **Step 8: Wire the viewer**

In `lib/features/library/page_viewer_screen.dart`:

Add the import:
```dart
import 'document_printer.dart';
```

Add a field to the widget + constructor:
```dart
  final DocumentPrinter printer;
```
and in the `const PageViewerScreen({...})` parameter list add:
```dart
    this.printer = const SystemDocumentPrinter(),
```

Add the handler near `_exportAllImages`:
```dart
  Future<void> _print() async {
    try {
      final file = await widget.repository.exportPdf(widget.documentId);
      await widget.printer.printPdf(file, name: _name);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sent to printer')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't print")),
      );
    }
  }
```

In the `PopupMenuButton`'s `onSelected`, add:
```dart
              if (v == 'print') unawaited(_print());
```

In `itemBuilder`'s list, add after the `export-all-images` item:
```dart
              PopupMenuItem<String>(
                value: 'print',
                key: Key('page-viewer-print'),
                child: Text('Print'),
              ),
```

- [ ] **Step 9: Run the test to verify it passes**

Run: `cd apps/mobile && flutter test test/features/library/page_viewer_print_test.dart`
Expected: PASS (2/2).

- [ ] **Step 10: Library group + analyze**

Run (set the DARTCV env if a test errors on `libdartcv`: `bash /Users/pablohpsilva/Documents/camscanner-light/scripts/setup-cv-host-test.sh` then export `DARTCV_LIB_PATH=/tmp/dartcv_lib/lib/libdartcv.dylib` + `DYLD_LIBRARY_PATH=/tmp/dartcv_lib/lib`):
`cd apps/mobile && flutter test test/features/library/ && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 11: Commit**

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/features/library/document_printer.dart apps/mobile/lib/features/library/library_dependencies.dart apps/mobile/lib/features/library/home_screen.dart apps/mobile/lib/features/library/page_viewer_screen.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/page_viewer_print_test.dart
git commit -m "feat(n1): print a document via DocumentPrinter seam + printing package"
```

---

### Task 2: BDD, on-device test, verify script, plans index

**Files:**
- Modify: `test/support/fake_library.dart` (inject the fake printer into `tempLibraryDependencies`)
- Create: `integration_test/n1_print_document.feature`
- Create step defs: `test/step/i_print_the_document.dart`, `test/step/i_see_the_print_confirmation.dart`
- Generate: `integration_test/n1_print_document_test.dart` (build_runner; committed)
- Create: `integration_test/n1_print_document_device_test.dart` (deterministic exportPdf→%PDF on device)
- Create: `scripts/verify/n1.sh` (repo root)
- Modify: `docs/superpowers/plans/00-plans-index.md`

- [ ] **Step 1: Inject the fake printer into the BDD launch deps**

In `test/support/fake_library.dart`, in `tempLibraryDependencies()`, add `printer: FakeDocumentPrinter(),` to the `LibraryDependencies(...)` constructor call, so the shared BDD launch never invokes the real printer (the OS sheet would hang the test). This is harmless for the existing scan BDDs (they never print).

- [ ] **Step 2: Write the `.feature`**

Create `integration_test/n1_print_document.feature`:

```gherkin
Feature: Print a document

  Scenario: Print the open document
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I capture and accept the first page
    And I tap Done
    And I open the first document
    And I print the document
    Then I see the print confirmation
```

- [ ] **Step 3: Write the new step definitions**

Create `test/step/i_print_the_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I print the document
Future<void> iPrintTheDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-page-menu')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-print')));
  await tester.pumpAndSettle();
}
```

Create `test/step/i_see_the_print_confirmation.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the print confirmation
Future<void> iSeeThePrintConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text('Sent to printer'), findsOneWidget);
}
```

> `the app is launched…`, `I tap the Scan button`, `I capture and accept the first page`, `I tap Done`, `I open the first document` already exist — reuse. Verify the generated step-function names match the generator's derivation; rename to match if needed.

- [ ] **Step 4: Generate the BDD test**

Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `integration_test/n1_print_document_test.dart` generated. If build_runner rewrote unrelated generated files, `git checkout` them so the commit stays scoped to N1.

- [ ] **Step 5: Write the deterministic on-device test**

Create `integration_test/n1_print_document_device_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/ocr_pdf_text_layer.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

String _dec(List<int> b) {
  final s = StringBuffer();
  for (final c in b) {
    s.writeCharCode(c);
  }
  return s.toString();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('exportPdf produces a valid PDF to print on device',
      (tester) async {
    final base = await Directory.systemTemp.createTemp('n1dev');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(textLayer: OcrPdfTextLayer()),
      warper: const HybridWarper(),
    );

    final jpeg = Uint8List.fromList(
        img.encodeJpg(img.Image(width: 8, height: 8), quality: 90));
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(DocumentsCompanion.insert(
        name: 'Doc', createdAt: now, modifiedAt: now));
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(rel, jpeg);
    await db.into(db.pages).insert(PagesCompanion.insert(
        documentId: id, position: 1, relativeImagePath: rel));

    final pdf = await repo.exportPdf(id);
    expect(_dec((await pdf.readAsBytes()).sublist(0, 4)), '%PDF');

    await db.close();
    await base.delete(recursive: true);
  });
}
```

- [ ] **Step 6: Write the verify script**

Create `scripts/verify/n1.sh` (repo root), mirroring `scripts/verify/o1.sh`:

```bash
#!/usr/bin/env bash
# Verify N1 (print a document) acceptance criteria.
# Run from repository root: bash scripts/verify/n1.sh
# VERIFY_SKIP_DEVICE=1 skips the on-device integration tests.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== N1 verification =="

require_tool flutter
require_tool pnpm

assert_file_has "DocumentPrinter seam exists" \
  "apps/mobile/lib/features/library/document_printer.dart" \
  "abstract interface class DocumentPrinter"

assert_file_has "printing dependency added" \
  "apps/mobile/pubspec.yaml" \
  "printing:"

assert_file_has "page viewer wires Print" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" \
  "page-viewer-print"

assert_file_has "BDD feature exists" \
  "apps/mobile/integration_test/n1_print_document.feature" \
  "Print a document"

assert_file_has "generated BDD test exists" \
  "apps/mobile/integration_test/n1_print_document_test.dart" \
  "print"

bash "$ROOT/scripts/setup-cv-host-test.sh"
export DARTCV_LIB_PATH="${DARTCV_LIB_PATH:-/tmp/dartcv_lib/lib/libdartcv.dylib}"
export DYLD_LIBRARY_PATH="/tmp/dartcv_lib/lib:${DYLD_LIBRARY_PATH:-}"

assert_cmd "host tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "flutter analyze clean" "No issues found" \
  bash -c "cd apps/mobile && flutter analyze --no-fatal-infos"

if [[ "${VERIFY_SKIP_DEVICE:-0}" == "1" ]]; then
  warn "VERIFY_SKIP_DEVICE=1 — on-device N1 tests skipped (must pass on a real device before gate)"
else
  assert_cmd "on-device print PDF test passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/n1_print_document_device_test.dart"
  assert_cmd "on-device BDD scenario passes" "All tests passed" \
    bash -c "cd apps/mobile && flutter test integration_test/n1_print_document_test.dart"
fi

echo "== N1 verification complete =="
```

Make it executable: `chmod +x scripts/verify/n1.sh`.

- [ ] **Step 7: Host verify + analyze**

Run: `cd apps/mobile && flutter test && flutter analyze --no-fatal-infos`
Expected: all pass; `No issues found`.

- [ ] **Step 8: Update the plans index**

In `docs/superpowers/plans/00-plans-index.md`, add after the M1 row:

```markdown
| N1 | Print a document | 12 | `2026-07-01-n1-print-document.md` | ✅ **built & gated** |
```

- [ ] **Step 9: Commit**

```bash
git add apps/mobile/test/support/fake_library.dart apps/mobile/integration_test/n1_print_document.feature apps/mobile/integration_test/n1_print_document_test.dart apps/mobile/integration_test/n1_print_document_device_test.dart apps/mobile/test/step/i_print_the_document.dart apps/mobile/test/step/i_see_the_print_confirmation.dart scripts/verify/n1.sh docs/superpowers/plans/00-plans-index.md
git commit -m "test(n1): BDD + on-device print tests, verify script, index"
```

---

## Self-Review

- **Spec coverage:** seam + production printer + deps threading + viewer action (Task 1), BDD + device + verify + index + BDD fake-printer injection (Task 2). ✅
- **Testability:** the native print sheet is never hit in tests — `FakeDocumentPrinter` (widget test + injected into `tempLibraryDependencies` for the BDD). ✅
- **Reuse:** printing reuses `exportPdf`'s searchable, scrubbed PDF. ✅
- **Placeholder scan:** complete code in every step; the `printing` version is pinned with a BLOCKED fallback if it won't resolve. ✅
- **Type consistency:** `DocumentPrinter.printPdf(File, {name})` identical across seam/fake/call site; `printer` param default `const SystemDocumentPrinter()` in both `LibraryDependencies` and `PageViewerScreen`. ✅
- **Out of scope kept out:** no fax, no share-to-print variants, no print settings UI. ✅
