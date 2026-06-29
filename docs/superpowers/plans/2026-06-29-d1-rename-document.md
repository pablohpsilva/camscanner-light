# D1 — Rename Document Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user rename a saved document from two surfaces — the viewer AppBar and the library-list row menu — sharing one dialog and one repository method.

**Architecture:** Add `repository.rename(id, newName)` (the only persistence surface) updating `name` + `modifiedAt`. A shared `showRenameDialog` (a private `StatefulWidget`) is the DRY UI unit both surfaces call. The viewer holds the title in local `_name` state (so it updates live); the list uses a per-row overflow menu. No schema change.

**Tech Stack:** Flutter 3.44.4, Dart, Drift/SQLite, `bdd_widget_test ^2.1.4`, Nx monorepo (`apps/mobile`, package `mobile`).

## Global Constraints

- **Privacy spine:** the name is read/edited/written entirely on-device (Drift/SQLite). No network, no new dependency.
- **No schema change:** `documents.name` and `documents.modifiedAt` already exist; `schemaVersion` stays `1`. Never edit `app_database.dart`'s schema.
- **Validation:** trim; non-empty required (Save disabled otherwise); 100-char cap; duplicate names allowed; unchanged-after-trim → no write.
- **Copy (verbatim):** dialog title `Rename document`; actions `Cancel` / `Save`; field label `Name`; failure SnackBar `Couldn't rename`.
- **Keys (verbatim):** `rename-dialog`, `rename-field`, `rename-cancel`, `rename-save`, `page-viewer-rename`, `document-menu-${id}`, `document-rename-${id}`.
- **Guards:** the viewer rename action is disabled iff `_loading || _error || _exporting` (delete's guard — **enabled when the document is empty**; no `_renaming` flag).
- **Found by KEY, never text:** an open menu shows the text `Rename` while the dialog title is `Rename document` — tests must target keys.
- **TDD/BDD, SOLID/KISS/DRY.** Tests: `pnpm nx run mobile:test --skip-nx-cache`; analyze: `pnpm nx run mobile:analyze --skip-nx-cache`; coverage floor 70 (excludes `*.g.dart`).
- All commands run from the repo root `/Users/pablohpsilva/Documents/camscanner-light` unless a step says `cd apps/mobile`.

## File Structure

| File | Responsibility | Task |
|---|---|---|
| `apps/mobile/lib/features/library/document_repository.dart` | add `rename` to the interface + `DocumentRenameException` | 1 |
| `apps/mobile/lib/features/library/drift/drift_document_repository.dart` | real `rename` (trim, bump `modifiedAt`, return updated `Document`) | 1 |
| `apps/mobile/test/support/fake_library.dart` | fake `rename` (mutate list + return; `throwOnRename`; `renamedTo` record) | 1 |
| `apps/mobile/test/features/library/drift_document_repository_test.dart` | repo `rename` tests (advancing clock, trim, throws) | 1 |
| `apps/mobile/lib/features/library/widgets/rename_dialog.dart` | **new** — `showRenameDialog` + private `_RenameDialog` | 2 |
| `apps/mobile/test/features/library/widgets/rename_dialog_test.dart` | **new** — dialog behaviour | 2 |
| `apps/mobile/lib/features/library/page_viewer_screen.dart` | rename action + `_name` state + `widget.name → _name` fix | 3 |
| `apps/mobile/test/features/library/page_viewer_screen_test.dart` | viewer rename tests + extend the in-flight test | 3 |
| `apps/mobile/lib/features/library/widgets/documents_list_view.dart` | per-row overflow menu + `onRename` | 4 |
| `apps/mobile/lib/features/library/home_screen.dart` | `_renameDocument` + wire `onRename` | 4 |
| `apps/mobile/test/features/library/documents_list_view_test.dart` | menu render/omit + onRename | 4 |
| `apps/mobile/test/features/library/home_screen_test.dart` | rename-from-list success + failure | 4 |
| `apps/mobile/integration_test/d1_rename.feature` (+ generated `d1_rename_test.dart`) | on-device rename via the list menu | 5 |
| `apps/mobile/test/step/i_open_the_rename_menu_for_the_first_document.dart` | **new** BDD step | 5 |
| `apps/mobile/test/step/i_rename_the_document_to.dart` | **new** BDD step | 5 |
| `scripts/verify/d1.sh` | **new** verification harness | 6 |

---

### Task 1: Repository `rename` (interface + Drift + Fake) — the migration surface

Adding `rename` to the interface is a compile-break across all implementers, so the interface, the Drift implementation, and the test fake land together. `grep` confirms these are the only three (`_FlakyPagesRepo` extends the fake and inherits `rename`).

**Files:**
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Produces: `Future<Document> rename(int documentId, String newName)` on `DocumentRepository`; `class DocumentRenameException implements Exception`. The Drift impl trims, bumps `modifiedAt` via `_clock`, returns the updated `Document`, and throws `DocumentRenameException` on empty-after-trim or no-such-row. The fake records into `List<String> renamedTo`, mutates its `documents` list, returns the updated `Document`, and throws when `throwOnRename` is set.

- [ ] **Step 1: Write the failing repo tests**

Append these tests to `apps/mobile/test/features/library/drift_document_repository_test.dart`, inside the existing `main()` (after the `exportPdf` tests, before the closing `}`). Add the import for the new exception type — it already imports `document_repository.dart`, so no new import is needed.

```dart
  test('rename updates the name and bumps modifiedAt; createdAt unchanged',
      () async {
    // The shared repo() helper uses a FIXED clock, which cannot show a bump.
    // Use the advancing-clock pattern (as 'listDocumentSummaries returns newest
    // first' does): create at T1, rename at T2.
    var t = DateTime.utc(2026, 6, 27, 10);
    final r = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: () => t,
      pdfBuilder: const PdfBuilder(),
    );
    final doc = await r.createFromCapture(capture);
    t = DateTime.utc(2026, 6, 27, 12); // clock advances before the rename

    final renamed = await r.rename(doc.id, 'Tax 2026');

    expect(renamed.name, 'Tax 2026');
    expect(renamed.createdAt, DateTime.utc(2026, 6, 27, 10));
    expect(renamed.modifiedAt, DateTime.utc(2026, 6, 27, 12),
        reason: 'rename bumps modifiedAt to the clock at rename time');

    final row = await (db.select(db.documents)
          ..where((d) => d.id.equals(doc.id)))
        .getSingle();
    expect(row.name, 'Tax 2026', reason: 'the new name is persisted');
    expect(row.modifiedAt, DateTime.utc(2026, 6, 27, 12));
  });

  test('rename trims surrounding whitespace', () async {
    final doc = await repo().createFromCapture(capture);
    final renamed = await repo().rename(doc.id, '   Spaced Name   ');
    expect(renamed.name, 'Spaced Name');
  });

  test('rename throws DocumentRenameException on an empty/whitespace name',
      () async {
    final doc = await repo().createFromCapture(capture);
    await expectLater(
      repo().rename(doc.id, '   '),
      throwsA(isA<DocumentRenameException>()),
    );
  });

  test('rename throws DocumentRenameException for a non-existent id', () async {
    await expectLater(
      repo().rename(99999, 'Whatever'),
      throwsA(isA<DocumentRenameException>()),
    );
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: FAIL — compile error, `The method 'rename' isn't defined for the type 'DriftDocumentRepository'` (and `DocumentRenameException` undefined).

- [ ] **Step 3: Add `rename` + `DocumentRenameException` to the interface**

In `apps/mobile/lib/features/library/document_repository.dart`, add the method to the `abstract interface class DocumentRepository` (after `exportPdf`):

```dart
  /// Renames [documentId] to [newName] (trimmed) and bumps modifiedAt. Returns
  /// the updated document. Throws [DocumentRenameException] when the trimmed
  /// name is empty or no document with that id exists. The name stays on-device.
  Future<Document> rename(int documentId, String newName);
```

And add the exception class after `DocumentExportException`:

```dart
class DocumentRenameException implements Exception {
  final String message;
  const DocumentRenameException(this.message);
  @override
  String toString() => 'DocumentRenameException: $message';
}
```

- [ ] **Step 4: Implement `rename` in the Drift repository**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`, add this method after `exportPdf` (this is the first `update`/`write` in the repo — the surrounding code uses `_db`, `_clock`, and `Value`/`DocumentsCompanion` from `package:drift/drift.dart`, already imported):

```dart
  @override
  Future<Document> rename(int documentId, String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty) {
      throw const DocumentRenameException('rename failed: empty name');
    }
    final modifiedUtc = _clock().toUtc();
    final updated = await (_db.update(_db.documents)
          ..where((t) => t.id.equals(documentId)))
        .write(DocumentsCompanion(
            name: Value(trimmed), modifiedAt: Value(modifiedUtc)));
    if (updated == 0) {
      throw const DocumentRenameException('rename failed: no such document');
    }
    final row = await (_db.select(_db.documents)
          ..where((t) => t.id.equals(documentId)))
        .getSingle();
    return Document(
      id: row.id,
      name: row.name,
      createdAt: row.createdAt,
      modifiedAt: row.modifiedAt,
    );
  }
```

- [ ] **Step 5: Implement `rename` in the fake**

In `apps/mobile/test/support/fake_library.dart`, add a flag + record to `FakeDocumentRepository`. Add a constructor parameter `this.throwOnRename = false` (alongside the other `throwOn*` flags) and these fields:

```dart
  final bool throwOnRename;
  final List<String> renamedTo = <String>[];
```

Then add the method (after `listDocumentSummaries`):

```dart
  @override
  Future<Document> rename(int documentId, String newName) async {
    if (throwOnRename) {
      throw const DocumentRenameException('fake: rename failed');
    }
    final trimmed = newName.trim();
    renamedTo.add(trimmed);
    final i = documents.indexWhere((d) => d.id == documentId);
    // Build the updated doc. modifiedAt is left as-is: host tests never assert
    // it (the list UI shows createdAt); the real Drift repo owns the clock+bump.
    final base = i >= 0
        ? documents[i]
        : Document(
            id: documentId,
            name: trimmed,
            createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
            modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42));
    final updated = Document(
      id: base.id,
      name: trimmed,
      createdAt: base.createdAt,
      modifiedAt: base.modifiedAt,
    );
    if (i >= 0) documents[i] = updated; // so listDocumentSummaries reflects it
    return updated;
  }
```

Add the constructor param in the existing parameter list, e.g.:

```dart
    this.throwOnDelete = false,
    this.throwOnExport = false,
    this.throwOnRename = false,
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: PASS — `All tests passed!` (the 4 new repo tests pass; the full suite still compiles because the fake now implements `rename`).

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/document_repository.dart \
        apps/mobile/lib/features/library/drift/drift_document_repository.dart \
        apps/mobile/test/support/fake_library.dart \
        apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(d1): repository.rename + DocumentRenameException (interface, Drift, fake)"
```

---

### Task 2: Shared rename dialog

**Files:**
- Create: `apps/mobile/lib/features/library/widgets/rename_dialog.dart`
- Test: `apps/mobile/test/features/library/widgets/rename_dialog_test.dart`

**Interfaces:**
- Produces: `Future<String?> showRenameDialog(BuildContext context, String currentName)` — returns the trimmed new name, or `null` on Cancel **or** when the trimmed value equals `currentName` (unchanged). Save is disabled while the trimmed value is empty. Field capped at 100 chars.

- [ ] **Step 1: Write the failing dialog tests**

Create `apps/mobile/test/features/library/widgets/rename_dialog_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/rename_dialog.dart';

void main() {
  // Pump a trivial host with a button that opens the dialog and stores the
  // result, so each test can assert what showRenameDialog returned.
  Future<void> pumpDialog(
    WidgetTester tester,
    String current, {
    required void Function(String?) onResult,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () async {
                final r = await showRenameDialog(context, current);
                onResult(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('pre-fills and fully selects the current name', (tester) async {
    await pumpDialog(tester, 'Scan 1', onResult: (_) {});
    final field =
        tester.widget<TextField>(find.byKey(const Key('rename-field')));
    expect(field.controller!.text, 'Scan 1');
    expect(field.controller!.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6));
  });

  testWidgets('Save is disabled when the field is empty/whitespace',
      (tester) async {
    await pumpDialog(tester, 'Scan 1', onResult: (_) {});
    await tester.enterText(find.byKey(const Key('rename-field')), '   ');
    await tester.pump();
    final save =
        tester.widget<TextButton>(find.byKey(const Key('rename-save')));
    expect(save.onPressed, isNull);
  });

  testWidgets('returns the trimmed new name on Save', (tester) async {
    String? result = '__unset__';
    await pumpDialog(tester, 'Scan 1', onResult: (r) => result = r);
    await tester.enterText(find.byKey(const Key('rename-field')), '  Taxes  ');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();
    expect(result, 'Taxes');
  });

  testWidgets('returns null on Cancel', (tester) async {
    String? result = '__unset__';
    await pumpDialog(tester, 'Scan 1', onResult: (r) => result = r);
    await tester.enterText(find.byKey(const Key('rename-field')), 'Changed');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-cancel')));
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('returns null when the name is unchanged', (tester) async {
    String? result = '__unset__';
    await pumpDialog(tester, 'Scan 1', onResult: (r) => result = r);
    await tester.tap(find.byKey(const Key('rename-save'))); // Save without editing
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('caps the field at 100 characters', (tester) async {
    await pumpDialog(tester, 'Scan 1', onResult: (_) {});
    final field =
        tester.widget<TextField>(find.byKey(const Key('rename-field')));
    expect(field.maxLength, 100);
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: FAIL — `Target of URI doesn't exist: 'package:mobile/features/library/widgets/rename_dialog.dart'`.

- [ ] **Step 3: Implement the dialog**

Create `apps/mobile/lib/features/library/widgets/rename_dialog.dart`:

```dart
import 'package:flutter/material.dart';

/// Shows a modal dialog to rename a document. Pre-fills [currentName] (fully
/// selected) and returns the trimmed new name, or null on cancel OR when the
/// trimmed value is unchanged (so the caller does no pointless write). Shared by
/// the viewer and the library list (DRY). The name never leaves the device.
Future<String?> showRenameDialog(BuildContext context, String currentName) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenameDialog(currentName: currentName),
  );
}

class _RenameDialog extends StatefulWidget {
  final String currentName;
  const _RenameDialog({required this.currentName});

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName)
      ..selection = TextSelection(
          baseOffset: 0, extentOffset: widget.currentName.length);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _canSave => _controller.text.trim().isNotEmpty;

  void _save() {
    final trimmed = _controller.text.trim();
    // Unchanged -> null so the caller skips the write (no pointless modifiedAt bump).
    Navigator.of(context).pop(trimmed == widget.currentName ? null : trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('rename-dialog'),
      title: const Text('Rename document'),
      content: TextField(
        key: const Key('rename-field'),
        controller: _controller,
        autofocus: true,
        maxLength: 100,
        decoration: const InputDecoration(labelText: 'Name'),
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) {
          if (_canSave) _save();
        },
      ),
      actions: [
        TextButton(
          key: const Key('rename-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('rename-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: PASS — `All tests passed!`

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/widgets/rename_dialog.dart \
        apps/mobile/test/features/library/widgets/rename_dialog_test.dart
git commit -m "feat(d1): shared showRenameDialog (trim, 100-char cap, unchanged->null)"
```

---

### Task 3: Viewer rename action + `_name` state

**Files:**
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart`
- Test: `apps/mobile/test/features/library/page_viewer_screen_test.dart`

**Interfaces:**
- Consumes: `showRenameDialog` (Task 2); `repository.rename` (Task 1).
- Produces: a rename `IconButton` keyed `page-viewer-rename`; the AppBar title and the `_exportPdf` preview argument both read local `_name` state.

- [ ] **Step 1: Write the failing viewer tests**

Add these tests to `apps/mobile/test/features/library/page_viewer_screen_test.dart` inside `main()` (after the existing export tests). They reuse the file's existing `pushViewer` helper (which pushes the viewer with `name: 'Scan X'`):

```dart
  testWidgets('rename: confirming Save updates the AppBar title',
      (tester) async {
    final repo = FakeDocumentRepository();
    await pushViewer(tester, repo, id: 3);

    await tester.tap(find.byKey(const Key('page-viewer-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'Receipts');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    expect(repo.renamedTo, contains('Receipts'));
    expect(find.widgetWithText(AppBar, 'Receipts'), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Scan X'), findsNothing);
  });

  testWidgets('rename is disabled in the error state', (tester) async {
    await pushViewer(tester, FakeDocumentRepository(throwOnGetPages: true));
    expect(find.byKey(const Key('page-viewer-error')), findsOneWidget);
    final btn = tester
        .widget<IconButton>(find.byKey(const Key('page-viewer-rename')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('rename failure shows an error SnackBar and stays',
      (tester) async {
    final repo = FakeDocumentRepository(throwOnRename: true);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-rename')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'New');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle(); // drive the async throw -> catch -> SnackBar

    expect(find.text("Couldn't rename"), findsOneWidget);
    expect(find.byType(PageViewerScreen), findsOneWidget);
  });
```

Then **edit the existing** `'both AppBar actions are disabled while an export is in flight'` test: rename its description and add the rename assertion. Replace the whole test with:

```dart
  testWidgets('all AppBar actions are disabled while an export is in flight',
      (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(exportGate: gate);
    await pushViewer(tester, repo);

    await tester.tap(find.byKey(const Key('page-viewer-export')));
    await tester.pump(); // start the export; gate holds it open
    IconButton btn(String k) =>
        tester.widget<IconButton>(find.byKey(Key(k)));
    expect(btn('page-viewer-rename').onPressed, isNull);
    expect(btn('page-viewer-export').onPressed, isNull);
    expect(btn('page-viewer-delete').onPressed, isNull);

    gate.complete();
    await tester.pump(); // process export completion + navigation (NOT settle — pdfx channel)
    await tester.pump();
    expect(find.byType(PdfPreviewScreen), findsOneWidget);
  });
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: FAIL — no widget with key `page-viewer-rename` found.

- [ ] **Step 3: Add the rename action + `_name` state to the viewer**

In `apps/mobile/lib/features/library/page_viewer_screen.dart`:

(a) Add the import near the other library imports:

```dart
import 'widgets/rename_dialog.dart';
```

(b) Add the `_name` field alongside the other state fields (after `int _current = 0;`):

```dart
  late String _name;
```

(c) Initialise it in `initState` (before `_load()`):

```dart
  @override
  void initState() {
    super.initState();
    _name = widget.name;
    _load();
  }
```

(d) Add the `_rename` method (e.g. after `_exportPdf`):

```dart
  Future<void> _rename() async {
    final newName = await showRenameDialog(context, _name);
    if (newName == null) return;
    if (!mounted) return;
    try {
      final updated = await widget.repository.rename(widget.documentId, newName);
      if (!mounted) return;
      setState(() => _name = updated.name);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't rename")),
      );
    }
  }
```

(e) Add the rename `IconButton` as the **first** entry in the AppBar `actions` list (before the export button):

```dart
          IconButton(
            key: const Key('page-viewer-rename'),
            icon: const Icon(Icons.edit_outlined),
            onPressed:
                (_loading || _error || _exporting) ? null : _rename,
          ),
```

(f) Replace `widget.name` with `_name` in **both** remaining places:
- the AppBar title: `title: Text(_name),`
- the export navigation: `PdfPreviewScreen(pdfPath: file.path, name: _name),`

After this, `widget.name` appears **exactly once** in the file — the `_name = widget.name` initializer.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: PASS — `All tests passed!`

- [ ] **Step 5: Verify the `widget.name` invariant locally**

Run: `grep -c "widget.name" apps/mobile/lib/features/library/page_viewer_screen.dart`
Expected: `1`

- [ ] **Step 6: Commit**

```bash
git add apps/mobile/lib/features/library/page_viewer_screen.dart \
        apps/mobile/test/features/library/page_viewer_screen_test.dart
git commit -m "feat(d1): viewer rename action + _name title state (renamed PDF preview shows new name)"
```

---

### Task 4: Library-list overflow menu + Home wiring

**Files:**
- Modify: `apps/mobile/lib/features/library/widgets/documents_list_view.dart`
- Modify: `apps/mobile/lib/features/library/home_screen.dart`
- Test: `apps/mobile/test/features/library/documents_list_view_test.dart`
- Test: `apps/mobile/test/features/library/home_screen_test.dart`

**Interfaces:**
- Consumes: `showRenameDialog` (Task 2); `repository.rename` (Task 1).
- Produces: `DocumentsListView` gains `final ValueChanged<DocumentSummary>? onRename;`; a per-row `PopupMenuButton` keyed `document-menu-${id}` with a `Rename` item keyed `document-rename-${id}`. `HomeScreen._renameDocument` shows the dialog, calls `repo.rename`, then `_load()`.

- [ ] **Step 1: Write the failing list-view tests**

Add to `apps/mobile/test/features/library/documents_list_view_test.dart` (inside `main()`):

```dart
  testWidgets('shows a per-document rename menu when onRename is set',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(summaries: [summary(1)], onRename: (_) {}),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-menu-1')), findsOneWidget);
  });

  testWidgets('omits the rename menu when onRename is null', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DocumentsListView(summaries: [summary(1)])),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('document-menu-1')), findsNothing);
  });

  testWidgets('selecting Rename invokes onRename with that summary',
      (tester) async {
    DocumentSummary? renamed;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DocumentsListView(
            summaries: [summary(2)], onRename: (s) => renamed = s),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-menu-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-2')));
    await tester.pumpAndSettle();
    expect(renamed, isNotNull);
    expect(renamed!.document.id, 2);
  });
```

- [ ] **Step 2: Write the failing home tests**

Add to `apps/mobile/test/features/library/home_screen_test.dart` (inside `main()`):

```dart
  testWidgets('renaming from the list menu updates the document name',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [
      Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
    ]);
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'Invoices');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    expect(repo.renamedTo, contains('Invoices'));
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsNothing);
  });

  testWidgets('a rename failure shows an error SnackBar', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnRename: true,
      documents: [
        Document(
            id: 1,
            name: 'Scan 2026-06-27 20.26.42',
            createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
            modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
      ],
    );
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'X');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't rename"), findsOneWidget);
  });
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: FAIL — `document-menu-1` not found (no menu yet); `onRename` not a named parameter of `DocumentsListView`.

- [ ] **Step 4: Add the overflow menu to `DocumentsListView`**

Replace the contents of `apps/mobile/lib/features/library/widgets/documents_list_view.dart` with:

```dart
import 'package:flutter/material.dart';

import '../document_summary.dart';
import 'document_thumbnail.dart';

/// Rich list of saved documents: thumbnail, name, date, page count. Newest
/// first (the repository orders the list). Each row has an optional overflow
/// menu (Rename) when [onRename] is provided.
class DocumentsListView extends StatelessWidget {
  final List<DocumentSummary> summaries;
  final ValueChanged<DocumentSummary>? onOpen;
  final ValueChanged<DocumentSummary>? onRename;
  const DocumentsListView({
    super.key,
    required this.summaries,
    this.onOpen,
    this.onRename,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('documents-list'),
      itemCount: summaries.length,
      itemBuilder: (context, i) {
        final s = summaries[i];
        final d = s.document;
        return ListTile(
          key: Key('document-tile-${d.id}'),
          leading: DocumentThumbnail(
              key: Key('document-thumb-${d.id}'), path: s.thumbnailPath),
          title: Text(d.name),
          subtitle: Text(
              '${_formatLocal(d.createdAt.toLocal())} · ${_pages(s.pageCount)}'),
          trailing: onRename == null
              ? null
              : PopupMenuButton<String>(
                  key: Key('document-menu-${d.id}'),
                  onSelected: (_) => onRename!(s),
                  itemBuilder: (context) => [
                    PopupMenuItem<String>(
                      key: Key('document-rename-${d.id}'),
                      value: 'rename',
                      child: const Text('Rename'),
                    ),
                  ],
                ),
          onTap: onOpen == null ? null : () => onOpen!(s),
        );
      },
    );
  }

  String _pages(int n) => n == 1 ? '1 page' : '$n pages';

  String _formatLocal(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
```

- [ ] **Step 5: Add `_renameDocument` to `HomeScreen` and wire `onRename`**

In `apps/mobile/lib/features/library/home_screen.dart`:

(a) Add the import near the other library imports:

```dart
import 'widgets/rename_dialog.dart';
```

(b) Add the method (e.g. after `_openDocument`):

```dart
  Future<void> _renameDocument(DocumentSummary s) async {
    final repo = _repository;
    if (repo == null) return;
    final newName = await showRenameDialog(context, s.document.name);
    if (newName == null) return;
    if (!mounted) return;
    try {
      await repo.rename(s.document.id, newName);
      await _load(); // refresh the list (no spinner; order is stable)
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't rename")),
      );
    }
  }
```

(c) Pass `onRename` to the list view in `build` (the `DocumentsListView(...)` constructor):

```dart
                  : DocumentsListView(
                      summaries: _summaries,
                      onOpen: _openDocument,
                      onRename: _renameDocument),
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `pnpm nx run mobile:test --skip-nx-cache`
Expected: PASS — `All tests passed!` (the existing list-view tests — `findsNWidgets(2)` on the name text and centre-tap → `onOpen` — still pass: the menu is an icon adding no text, on a right-edge hit-target. Those existing tests construct `DocumentsListView` without `onRename`, so the menu is omitted there anyway.)

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/widgets/documents_list_view.dart \
        apps/mobile/lib/features/library/home_screen.dart \
        apps/mobile/test/features/library/documents_list_view_test.dart \
        apps/mobile/test/features/library/home_screen_test.dart
git commit -m "feat(d1): library-list rename via per-row overflow menu"
```

---

### Task 5: BDD integration (rename via the list menu, android + ios)

**Files:**
- Create: `apps/mobile/integration_test/d1_rename.feature`
- Create: `apps/mobile/test/step/i_open_the_rename_menu_for_the_first_document.dart`
- Create: `apps/mobile/test/step/i_rename_the_document_to.dart`
- Generated (do **not** hand-edit): `apps/mobile/integration_test/d1_rename_test.dart`

**Interfaces:**
- Consumes: the list menu keys (Task 4) and dialog keys (Task 2); the reused steps `theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage` (wires the real `tempLibraryDependencies` repo), `iTapTheScanButton`, `iTapTheShutter`, `iTapAccept`, `iSeeText` (parameterised; the `{'…'}` whitespace form is proven by `a2_scan_permission.feature`).

- [ ] **Step 1: Write the new step files**

Create `apps/mobile/test/step/i_open_the_rename_menu_for_the_first_document.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the rename menu for the first document
Future<void> iOpenTheRenameMenuForTheFirstDocument(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('document-menu-1')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('document-rename-1')));
  await tester.pumpAndSettle();
}
```

Create `apps/mobile/test/step/i_rename_the_document_to.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I rename the document to {'New Name'}
Future<void> iRenameTheDocumentTo(WidgetTester tester, String name) async {
  // enterText replaces the pre-filled name (no manual clear needed).
  await tester.enterText(find.byKey(const Key('rename-field')), name);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('rename-save')));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 2: Write the feature file**

Create `apps/mobile/integration_test/d1_rename.feature`:

```gherkin
Feature: Rename a document

  Scenario: Rename a document from the library list
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    And I open the rename menu for the first document
    And I rename the document to {'Field Notes'}
    Then I see {'Field Notes'} text
```

- [ ] **Step 3: Generate the integration test**

Run: `cd apps/mobile && dart run build_runner build`
Expected: `Built with build_runner` — creates `apps/mobile/integration_test/d1_rename_test.dart`.

- [ ] **Step 4: Verify the generated test is non-vacuous (calls the real steps)**

Run: `grep -E "iOpenTheRenameMenuForTheFirstDocument|iRenameTheDocumentTo|iSeeText" apps/mobile/integration_test/d1_rename_test.dart`
Expected: three matching call lines (e.g. `await iOpenTheRenameMenuForTheFirstDocument(tester);`, `await iRenameTheDocumentTo(tester, 'Field Notes');`, `await iSeeText(tester, 'Field Notes');`). If any step is missing or generated as an empty stub, the step text and the step file name disagree — fix the phrasing.

- [ ] **Step 5: Run the integration test on the Android emulator**

Run (a booted Android emulator required):
`cd apps/mobile && flutter test integration_test/d1_rename_test.dart -d emulator-5554`
(Use your booted emulator id; `adb devices` lists it.)
Expected: `All tests passed!`

- [ ] **Step 6: Run the integration test on the iOS simulator**

Run (a booted iOS simulator required):
`cd apps/mobile && flutter test integration_test/d1_rename_test.dart -d "iPhone 15 Pro"`
(Use your booted simulator name; `xcrun simctl list devices booted` lists it.)
Expected: `All tests passed!`

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/integration_test/d1_rename.feature \
        apps/mobile/integration_test/d1_rename_test.dart \
        apps/mobile/test/step/i_open_the_rename_menu_for_the_first_document.dart \
        apps/mobile/test/step/i_rename_the_document_to.dart
git commit -m "test(d1): BDD integration — rename a document from the library list (android+ios)"
```

---

### Task 6: Verification harness `scripts/verify/d1.sh`

**Files:**
- Create: `scripts/verify/d1.sh`

**Interfaces:**
- Consumes: `scripts/verify/lib.sh` helpers (`require_tool`, `pass`, `fail`, `assert_file_has`, `assert_cmd`, `assert_coverage_floor`, `verify_integration_android`, `verify_integration_ios`, `verify_summary`; `$ROOT`, `$ADB`).

- [ ] **Step 1: Write the script**

Create `scripts/verify/d1.sh`:

```bash
#!/usr/bin/env bash
# Verify D1 (rename document) acceptance criteria.
# Run: bash scripts/verify/d1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (rename on a physical device — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== D1 verification =="

require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence ----
assert_file_has "repository declares rename" \
  "apps/mobile/lib/features/library/document_repository.dart" "Future<Document> rename("
assert_file_has "DocumentRenameException exists" \
  "apps/mobile/lib/features/library/document_repository.dart" "class DocumentRenameException"
assert_file_has "Drift implements rename" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "Future<Document> rename("
assert_file_has "shared rename dialog exists" \
  "apps/mobile/lib/features/library/widgets/rename_dialog.dart" "Future<String?> showRenameDialog"
assert_file_has "rename dialog field key" \
  "apps/mobile/lib/features/library/widgets/rename_dialog.dart" "rename-field"
assert_file_has "rename dialog save key" \
  "apps/mobile/lib/features/library/widgets/rename_dialog.dart" "rename-save"
assert_file_has "viewer has the rename action" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "page-viewer-rename"
assert_file_has "list view has the per-row menu" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "document-menu-"
assert_file_has "no schema bump (schemaVersion stays 1)" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 1;"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- (A) _name guard invariant: a renamed-then-exported PDF shows the NEW name ----
assert_file_has "viewer title is local _name state" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "_name = widget.name"
WIDGET_NAME_COUNT="$(grep -c "widget.name" apps/mobile/lib/features/library/page_viewer_screen.dart)"
if [ "$WIDGET_NAME_COUNT" = "1" ]; then
  pass "widget.name used exactly once (only the _name initializer; title + export read _name)"
else
  fail "widget.name appears $WIDGET_NAME_COUNT times (expected 1: the _name initializer) — title or export PDF may show a stale name after rename"
fi

# ---- No-empty-stub guard ----
assert_file_has "step: open-rename-menu is real (not a stub)" \
  "apps/mobile/test/step/i_open_the_rename_menu_for_the_first_document.dart" "document-rename-"
assert_file_has "step: rename-to enters text (not a stub)" \
  "apps/mobile/test/step/i_rename_the_document_to.dart" "enterText"
assert_file_has "step: rename-to taps Save (not a stub)" \
  "apps/mobile/test/step/i_rename_the_document_to.dart" "rename-save"
assert_file_has "generated d1 test calls the open-menu step" \
  "apps/mobile/integration_test/d1_rename_test.dart" "iOpenTheRenameMenuForTheFirstDocument(tester)"
assert_file_has "generated d1 test calls the rename step" \
  "apps/mobile/integration_test/d1_rename_test.dart" "iRenameTheDocumentTo(tester"
assert_file_has "generated d1 test calls the assertion step" \
  "apps/mobile/integration_test/d1_rename_test.dart" "iSeeText(tester"

# ---- Generated code current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (d1 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/d1_rename_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria ----
assert_cmd "d1 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android d1_rename_test.dart
verify_integration_ios d1_rename_test.dart

# ---- Opt-in REAL_DEVICE Tier-3 ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): rename a document from the list menu AND from the viewer; confirm the new name shows in the list and on the viewer AppBar."
fi

verify_summary
```

- [ ] **Step 2: Make it executable and run the full gate**

Run:
```bash
chmod +x scripts/verify/d1.sh
bash scripts/verify/d1.sh
```
Expected: `GATE: PASS` with all assertions passing (requires a booted Android emulator + iOS simulator). If no devices are booted, run `VERIFY_SKIP_DEVICE=1 bash scripts/verify/d1.sh` and confirm it reports `GATE: FAIL` (fail-closed negative control), then run the full gate once devices are up.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify/d1.sh
git commit -m "test(d1): verification harness scripts/verify/d1.sh"
```

---

## Self-Review

**1. Spec coverage** (against `docs/superpowers/specs/2026-06-29-d1-rename-document-design.md`):
- `repository.rename` + `DocumentRenameException` → Task 1. ✓
- Migration surface (3 implementers, one task) → Task 1. ✓
- Fake mutate + return + `throwOnRename` + `renamedTo` → Task 1. ✓
- `showRenameDialog` (select-all, 100-cap, Save-enable, unchanged→null, copy, keys) → Task 2. ✓
- Viewer rename action + guard + `_name` + `widget.name → _name` fix → Task 3. ✓
- Extended in-flight test → Task 3 Step 1. ✓
- List overflow menu (by key) + `onRename` + omit-when-null + Home `_renameDocument` + `_load()` → Task 4. ✓
- Existing list tests survive → Task 4 Step 6 note. ✓
- Repo tests: advancing-clock `modifiedAt`, trim, throws (empty, missing id), returns Document → Task 1 Step 1. ✓
- Dialog tests (all 6) → Task 2 Step 1. ✓
- Viewer tests (present/disabled-in-error/confirm-updates-title/failure-SnackBar) + ENABLED-when-empty (no empty-disabled test, by design) → Task 3. ✓
- List/Home tests → Task 4. ✓
- BDD integration via list menu, android+ios, 2 new steps, reuse i_see_text, punctuation-free phrasing → Task 5. ✓
- `d1.sh`: static asserts, (A) guard invariant (grep-implementable), no-stub guard, codegen+diff, test+analyze+coverage, integration android+ios, fail-closed, REAL_DEVICE Tier-3 → Task 6. ✓
- 8 acceptance criteria: 1 (viewer→Task 3 + 4), 2 (list→Task 4 + 5), 3 (persist+bump→Task 1), 4 (empty rejected→Task 1+2), 5 (unchanged→Task 2), 6 (failure→Task 3+4), 7 (`_name` fix→Task 3 + d1.sh invariant), 8 (privacy→code review, no new dep). ✓

**2. Placeholder scan:** No TBD/TODO/"handle errors"/"similar to". Every code step shows complete code; every command shows expected output. ✓

**3. Type consistency:** `rename(int documentId, String newName) → Future<Document>` and `DocumentRenameException` are identical across the interface (Task 1 Step 3), Drift (Step 4), fake (Step 5), and all callers (Tasks 3–4). `showRenameDialog(BuildContext, String) → Future<String?>` is identical across Task 2, Task 3 (`_rename`), and Task 4 (`_renameDocument`). Keys (`page-viewer-rename`, `document-menu-${id}`, `document-rename-${id}`, `rename-field`, `rename-save`) match between production, tests, steps, and `d1.sh`. Step camelCase names (`iOpenTheRenameMenuForTheFirstDocument`, `iRenameTheDocumentTo`, `iSeeText`) match the feature text, the step files, and the `d1.sh` assertions. ✓
