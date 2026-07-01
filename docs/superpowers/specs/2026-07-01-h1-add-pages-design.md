# H1 Add Multiple Pages — Implementation Design

**Date:** 2026-07-01
**Status:** Approved (design)
**Sub-project:** 1 — Core scan pipeline
**Depends on:** B1 (`DriftDocumentRepository`, `SaveController`), G4 (`CaptureReviewScreen` with FilterPickerStrip)
**Feeds:** H2 (thumbnail strip)
**Step in roadmap:** H1 — Add multiple pages (first of H. Multi-page series)

## Purpose

Enable capturing multiple pages into a single document in one scanning session.
After the first page is saved, the camera stays open so the user can scan more pages.
Each subsequent capture is appended to the same document at the next position.
A **Done ✓** button lets the user finish and return home.

The document model (one Document → many Pages with `position`) already exists in the
DB schema; this step activates it by wiring the data layer and camera UX.

### In scope
- `DocumentRepository.addPageToDocument()` — new interface method
- `DriftDocumentRepository.addPageToDocument()` — implementation (same image pipeline as `createFromCapture`, position = MAX + 1, transaction-safe)
- `SaveController.addPage()` — new method wrapping `addPageToDocument`
- `CameraScreen` add-page mode: stays open after first Accept, AppBar shows page count + Done ✓ button, subsequent Accepts append to same document
- BDD scenario: two pages in one session → same document, two pages
- `scripts/verify/h1.sh`

### Out of scope
- Adding pages to an existing document later from the document viewer (requires H2 thumbnail strip UI)
- Thumbnail strip / page grid (H2)
- Reorder, delete, retake (H3/H4)
- Multi-page PDF (H5)

---

## Architecture

### Modified: `lib/features/library/document_repository.dart`

Add one new abstract method and one new exception class:

```dart
/// Appends a new page to [documentId] at position MAX(current)+1.
/// Returns the position of the newly created page (1-based).
/// Throws [DocumentSaveException] when [documentId] does not exist or has no
/// pages (a document without pages is an inconsistent state).
Future<int> addPageToDocument(
  int documentId,
  CapturedImage capture, {
  CropCorners? corners,
  ImageEnhancer? enhancer,
});
```

### Modified: `lib/features/library/drift/drift_document_repository.dart`

New `addPageToDocument()` method:

```dart
@override
Future<int> addPageToDocument(
  int documentId,
  CapturedImage capture, {
  CropCorners? corners,
  ImageEnhancer? enhancer,
}) async {
  try {
    final position = await _db.transaction(() async {
      // Query MAX(position) — throws if document has no pages.
      final maxRow = await (_db.select(_db.pages)
            ..where((p) => p.documentId.equals(documentId))
            ..orderBy([(p) => OrderingTerm.desc(p.position)])
            ..limit(1))
          .getSingleOrNull();
      if (maxRow == null) {
        throw DocumentSaveException('document $documentId has no pages');
      }
      final newPosition = maxRow.position + 1;
      final rel = _fileStore.relativeFor(documentId, newPosition);
      late final Uint8List scrubbed;
      try {
        final raw = await File(capture.path).readAsBytes();
        scrubbed = _scrubber.scrub(Uint8List.fromList(raw));
        final isFullFrame = corners == null || corners == CropCorners.fullFrame;
        Uint8List bytesToStore = scrubbed;
        if (enhancer != null && isFullFrame) {
          try {
            bytesToStore = await enhancer.enhance(scrubbed);
          } catch (_) {}
        }
        await _fileStore.writeRelative(rel, bytesToStore);
      } catch (e) {
        rethrow;
      }
      String? flatRel;
      if (corners != null && corners != CropCorners.fullFrame) {
        try {
          Uint8List? flat = await _warper.warp(scrubbed, corners);
          if (flat != null) {
            Uint8List flatBytes = flat;
            if (enhancer != null) {
              try {
                flatBytes = await enhancer.enhance(flat);
              } catch (_) {}
            }
            flatRel = _fileStore.flatRelativeFor(documentId, newPosition);
            await _fileStore.writeRelative(flatRel, flatBytes);
          }
        } catch (_) {}
      }
      await _db.into(_db.pages).insert(
            PagesCompanion.insert(
                documentId: documentId,
                position: newPosition,
                relativeImagePath: rel,
                corners: Value(corners?.toStorage()),
                flatRelativePath: Value(flatRel)),
          );
      // Bump modifiedAt on the parent document.
      await (_db.update(_db.documents)
            ..where((d) => d.id.equals(documentId)))
          .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
      return newPosition;
    });
    await _deleteTempSource(capture.path);
    return position;
  } catch (e) {
    if (e is DocumentSaveException) rethrow;
    throw DocumentSaveException('addPage failed: $e');
  }
}
```

**Key differences from `createFromCapture`:**
- Does NOT insert a `Documents` row — appends to existing document
- Queries MAX(position) and inserts at +1
- Bumps `modifiedAt` on the parent document
- Throws `DocumentSaveException` if the document has no pages (inconsistent state)

### Modified: `lib/features/library/save_controller.dart`

New `addPage()` method:

```dart
/// Appends a captured page to [documentId]. Returns the page position
/// (1-based) on success, or null on failure.
Future<int?> addPage(
  CapturedImage image,
  int documentId, {
  CropCorners corners = CropCorners.fullFrame,
  ImageEnhancer enhancer = const NoneEnhancer(),
}) async {
  if (_disposed || _status == SaveStatus.saving) return null;
  _set(SaveStatus.saving);
  try {
    final position = await _repository.addPageToDocument(
        documentId, image, corners: corners, enhancer: enhancer);
    if (_disposed) return null;
    _set(SaveStatus.idle);
    return position;
  } catch (_) {
    if (_disposed) return null;
    _set(SaveStatus.error);
    return null;
  }
}
```

### Modified: `lib/features/scan/camera_screen.dart`

**New state variables in `_CameraScreenState`:**

```dart
int? _activeDocId;    // null until first page saved
String? _activeDocName;
int _pageCount = 0;   // increments after each successful save
```

**Modified `_onAccept`:**

```dart
Future<void> _onAccept(
    CapturedImage image, CropCorners corners, ImageEnhancer enhancer) async {
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  if (_activeDocId == null) {
    // First page: create new document.
    final doc = await _saveController.save(image,
        corners: corners, enhancer: enhancer);
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save document. Try again.")),
      );
      return;
    }
    setState(() {
      _activeDocId = doc.id;
      _activeDocName = doc.name;
      _pageCount = 1;
    });
    navigator.pop(); // dismiss review, stay in camera
  } else {
    // Subsequent pages: append to active document.
    final position = await _saveController.addPage(image, _activeDocId!,
        corners: corners, enhancer: enhancer);
    if (!mounted) return;
    if (position == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save page. Try again.")),
      );
      return;
    }
    setState(() => _pageCount = position);
    navigator.pop();
  }
}
```

**Done button handler (new):**
```dart
void _onDone() {
  Navigator.of(context).popUntil((route) => route.isFirst);
}
```

**Modified `build()` — AppBar:**

```dart
appBar: AppBar(
  title: _pageCount == 0
      ? const Text('Scan')
      : Text('$_pageCount page${_pageCount == 1 ? '' : 's'} saved'),
  actions: _pageCount > 0
      ? [
          IconButton(
            key: const Key('camera-done'),
            icon: const Icon(Icons.check),
            tooltip: 'Done scanning',
            onPressed: _onDone,
          ),
        ]
      : null,
),
```

No changes to the constructor signature — `CameraScreen` remains `const CameraScreen({super.key, dependencies, required repository})`.

---

## Data Flow

```
CameraScreen._onShutter()
  → CaptureReviewScreen (pushed)
  → user taps Accept → _onAccept(image, corners, enhancer)

First page (activeDocId == null):
  → SaveController.save()
  → DriftDocumentRepository.createFromCapture()
  → Document(id=42, name="Scan 2026-07-01 ...", ...)
  → setState(_activeDocId=42, _pageCount=1)
  → navigator.pop() → back to CameraScreen
  → AppBar: "1 page saved" + Done ✓

Second page:
  → SaveController.addPage(image, documentId=42, ...)
  → DriftDocumentRepository.addPageToDocument(42, ...)
    → MAX(position)=1 → insert at position=2
    → returns 2
  → setState(_pageCount=2)
  → navigator.pop() → back to CameraScreen
  → AppBar: "2 pages saved" + Done ✓

User taps Done:
  → popUntil(isFirst) → HomeScreen
  → _load() refreshes list, document shows "2 pages"
```

---

## Keys (testable anchors)

| Widget | Key |
|--------|-----|
| Done button (add-page mode) | `Key('camera-done')` |

---

## Global Constraints

- JPEG quality 92 for saved pages (same as `createFromCapture`)
- `img.bakeOrientation()` before pixel processing — handled by enhancers (existing behaviour)
- Transaction-safe: `addPageToDocument` is one DB transaction; rolls back on error
- OCP: `FilterPickerStrip`, `EnhancerMode`, all enhancers, `DriftDocumentRepository.createFromCapture()` must not be modified
- Error resilience: `addPage` failure → snackbar, camera stays in add-page mode (does not reset `_activeDocId`)
- `CameraScreen` constructor signature unchanged — no breaking change for existing tests/wiring

---

## BDD Scenarios

**Feature file:** `integration_test/h1_add_pages.feature`

```gherkin
Feature: H1 Add multiple pages to a document

  Scenario: Accepting first page keeps camera open
    Given the camera screen is open
    When I capture and accept the first page
    Then the camera screen shows the Done button

  Scenario: Two pages are saved to the same document
    Given the camera screen is open
    When I capture and accept the first page
    And I capture and accept the second page
    And I tap Done
    Then the document has 2 pages
```

---

## Testing Strategy

| Layer | What is tested |
|-------|----------------|
| Unit: `addPageToDocument` | Two sequential calls → positions 1 (createFromCapture) and 2 (addPageToDocument) |
| Unit: `addPageToDocument` | Non-existent documentId → throws `DocumentSaveException` |
| Unit: `addPageToDocument` | `modifiedAt` bumped on parent document |
| Unit: `addPageToDocument` | Full-frame + crop paths (enhancement applied correctly) |
| Unit: `SaveController.addPage` | Returns position on success; returns null on repository error |
| Widget: `CameraScreen` | After first Accept: `Key('camera-done')` present; AppBar title "1 page saved" |
| Widget: `CameraScreen` | After second Accept: AppBar title "2 pages saved" |
| Widget: `CameraScreen` | Done button calls `popUntil(isFirst)` (navigator pop) |
| Widget: `CameraScreen` | addPage failure → snackbar shown; camera stays in add-page mode |
| Widget: `CameraScreen` | Before any Accept: `Key('camera-done')` absent; title "Scan" |
| BDD | First accept → camera-done button visible |
| BDD | Two accepts + Done → document has 2 pages |
| Static | `addPageToDocument` in `document_repository.dart` |
| Static | `Key('camera-done')` in `camera_screen.dart` |

---

## Verify Script

`scripts/verify/h1.sh` — follows `lib.sh` pattern:
- Static: `addPageToDocument` in `document_repository.dart`; `addPageToDocument` in `drift_document_repository.dart`; `addPage` in `save_controller.dart`; `Key('camera-done')` in `camera_screen.dart`; feature file exists; generated test exists
- `pnpm nx run mobile:test` passes
- `pnpm nx run mobile:analyze` clean
- Coverage ≥ 70%
- BDD device gate (skippable with `VERIFY_SKIP_DEVICE=1`)

---

## Deliverable (user-testable)

Take a scan → review screen opens → tap Accept → camera stays open, AppBar shows "1 page saved" with a ✓ Done button. Take another shot → Accept → AppBar shows "2 pages saved". Tap ✓ Done → back to document list → the document shows "2 pages."

**Test it by:**
1. Open app → tap Scan → capture a page → Accept.
2. Camera stays open with "1 page saved" + Done button.
3. Capture a second page → Accept → "2 pages saved."
4. Tap Done → document list shows the document with 2 pages.
5. Open the document → both pages are visible in the viewer.

---

## Acceptance Criteria

- [ ] `DocumentRepository` has `addPageToDocument()` — *static*
- [ ] `addPageToDocument` inserts at MAX(position)+1 in one transaction — *unit*
- [ ] `addPageToDocument` throws `DocumentSaveException` for non-existent documentId — *unit*
- [ ] `addPageToDocument` bumps `modifiedAt` on parent document — *unit*
- [ ] `SaveController.addPage()` returns position on success, null on failure — *unit*
- [ ] After first Accept: camera stays open, AppBar shows "1 page saved", Done ✓ visible — *widget*
- [ ] Done ✓ tapped → navigates to HomeScreen — *widget*
- [ ] Second Accept: AppBar shows "2 pages saved" — *widget*
- [ ] addPage failure: snackbar shown, camera stays in add-page mode — *widget*
- [ ] BDD: first accept → Done button visible — *integration*
- [ ] BDD: two accepts + Done → document has 2 pages in DB — *integration*
- [ ] All host tests pass; analyze clean; coverage ≥ 70% — *verify script*

---

> **Definition of Done gate:** Per `00-overview-roadmap.md`, this feature is not done until
> every acceptance criterion above maps to a passing test, the full suite is green, quality
> gates pass, and the work is reviewed and double-checked.
