# E1 — Corner Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the user adjust four crop corners over a captured document on the Review screen, and persist that quad as per-page metadata — non-destructively (image bytes unchanged).

**Architecture:** A pure `CropCorners` value model (normalized, role-tagged, fail-soft serialization); a controlled `CropOverlay` widget (fitted-rect math, draggable clamped handles); `CaptureReviewScreen` becomes stateful, decodes the EXIF-applied natural size, hosts the overlay, and passes the quad up on Accept; the repository persists it in a new nullable `Pages.corners` column behind a tested schemaVersion 1→2 migration. E2 (later) flattens from these corners; E1 ships only overlay + persistence.

**Tech Stack:** Flutter 3.44.4, Nx monorepo (`apps/mobile`, package `mobile`), Drift/SQLite, bdd_widget_test ^2.1.4.

## Global Constraints

- **Non-destructive:** Accept persists corners as metadata; stored image bytes stay the original EXIF-scrubbed capture. Do NOT flatten/transform pixels in E1.
- **Coordinate frame (contract to E2):** corners are normalized `[0..1]` in the **display (EXIF-applied) frame**, top-left origin, **role-tagged** `topLeft/topRight/bottomRight/bottomLeft` (never a `List<Offset>`). Natural size MUST come from the framework decoder (EXIF-applied), never a raw JPEG header read. E1 clamps to bounds only — NO convexity/self-intersection enforcement; E2 must honor EXIF Orientation and guard degenerate quads.
- **Schema:** `schemaVersion` 1→2 adds ONE nullable `Pages.corners` column via `onUpgrade addColumn`; old/null rows read back as `CropCorners.fullFrame`. Keep the `beforeOpen` FK pragma. The migration MUST be tested.
- **Privacy spine:** on-device only, no network, **no new runtime dependency**, EXIF still scrubbed (Orientation preserved), relative paths. (`sqlite3` is added as a TEST-ONLY dev dependency for the migration test — already transitive via drift; not a runtime/privacy dep.)
- **a11y:** crop handles and the Reset control carry semantic labels (app-wide standard set in the a11y pass).
- **Commands:** tests `pnpm nx run mobile:test --skip-nx-cache` (marker `All tests passed!`); analyze `pnpm nx run mobile:analyze --skip-nx-cache` (marker `Successfully ran target analyze`); codegen `cd apps/mobile && dart run build_runner build` (marker `Built with build_runner`).
- **Step text** (BDD) is punctuation-free (avoids bdd_widget_test silent-empty stubs).
- Never stage `apps/mobile/ios/Runner.xcodeproj/project.pbxproj`.

## File Structure

| File | Responsibility | Task |
|------|----------------|------|
| `apps/mobile/lib/features/library/crop_corners.dart` | NEW. Pure `CropCorners` model + serialization. | 1 |
| `apps/mobile/test/features/library/crop_corners_test.dart` | NEW. Unit tests. | 1 |
| `apps/mobile/lib/features/library/drift/app_database.dart` | MODIFY. `Pages.corners`, schemaVersion 2, onUpgrade. | 2 |
| `apps/mobile/pubspec.yaml` | MODIFY. Add `sqlite3` to dev_dependencies (test-only). | 2 |
| `apps/mobile/test/features/library/drift/migration_test.dart` | NEW. Hand-rolled v1→v2 migration test. | 2 |
| `apps/mobile/lib/features/library/page_image.dart` | MODIFY. Add `corners` (default fullFrame). | 3 |
| `apps/mobile/lib/features/library/document_repository.dart` | MODIFY. `createFromCapture({CropCorners? corners})`. | 3 |
| `apps/mobile/lib/features/library/drift/drift_document_repository.dart` | MODIFY. Write/read corners. | 3 |
| `apps/mobile/test/support/fake_library.dart` | MODIFY. Fake records corners; returns new PageImage. | 3 |
| `apps/mobile/test/features/library/drift_document_repository_test.dart` | MODIFY. Corner round-trip tests. | 3 |
| `apps/mobile/lib/features/scan/widgets/crop_overlay.dart` | NEW. `CropOverlay` widget. | 4 |
| `apps/mobile/test/features/scan/widgets/crop_overlay_test.dart` | NEW. Widget tests. | 4 |
| `apps/mobile/lib/features/scan/capture_review_screen.dart` | MODIFY → StatefulWidget; overlay + decode + reset; `onAccept` signature. | 5 |
| `apps/mobile/lib/features/library/save_controller.dart` | MODIFY. `save(image, {corners})`. | 5 |
| `apps/mobile/lib/features/scan/camera_screen.dart` | MODIFY. Pass corners through. | 5 |
| `apps/mobile/test/features/scan/capture_review_screen_test.dart` | MIGRATE + extend. | 5 |
| `apps/mobile/integration_test/e1_crop.feature` (+ generated `_test.dart`) | NEW. BDD wiring smoke test. | 6 |
| `apps/mobile/test/step/i_see_the_crop_overlay.dart` | NEW step. | 6 |
| `apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart` | NEW step. | 6 |
| `scripts/verify/e1.sh` | NEW. The E1 gate. | 7 |

---

### Task 1: `CropCorners` model

**Files:**
- Create: `apps/mobile/lib/features/library/crop_corners.dart`
- Test: `apps/mobile/test/features/library/crop_corners_test.dart`

**Interfaces:**
- Consumes: `Offset` from `package:flutter/painting.dart` (pure — no widgets).
- Produces: `class CropCorners` with `Offset topLeft, topRight, bottomRight, bottomLeft`; `const CropCorners({required ...})`; `static const CropCorners fullFrame`; `CropCorners clamp()`; `String toStorage()`; `static CropCorners? tryParse(String?)`; value `==`/`hashCode`.

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/library/crop_corners_test.dart`:

```dart
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';

void main() {
  test('fullFrame is the unit square in role order', () {
    expect(CropCorners.fullFrame.topLeft, const Offset(0, 0));
    expect(CropCorners.fullFrame.topRight, const Offset(1, 0));
    expect(CropCorners.fullFrame.bottomRight, const Offset(1, 1));
    expect(CropCorners.fullFrame.bottomLeft, const Offset(0, 1));
  });

  test('clamp pulls every corner into [0,1]x[0,1]', () {
    const c = CropCorners(
      topLeft: Offset(-0.2, -0.5), topRight: Offset(1.3, 0.1),
      bottomRight: Offset(2.0, 1.4), bottomLeft: Offset(-1.0, 0.9));
    final r = c.clamp();
    expect(r.topLeft, const Offset(0, 0));
    expect(r.topRight, const Offset(1, 0.1));
    expect(r.bottomRight, const Offset(1, 1));
    expect(r.bottomLeft, const Offset(0, 0.9));
  });

  test('toStorage <-> tryParse round-trips in role order', () {
    const c = CropCorners(
      topLeft: Offset(0.1, 0.2), topRight: Offset(0.9, 0.15),
      bottomRight: Offset(0.85, 0.95), bottomLeft: Offset(0.05, 0.9));
    final parsed = CropCorners.tryParse(c.toStorage());
    expect(parsed, c);
  });

  test('tryParse is fail-soft on bad input (never throws)', () {
    expect(CropCorners.tryParse(null), isNull);
    expect(CropCorners.tryParse(''), isNull);
    expect(CropCorners.tryParse('0.1,0.2,0.3'), isNull);            // wrong count
    expect(CropCorners.tryParse('a,b,c,d,e,f,g,h'), isNull);        // non-numeric
    expect(CropCorners.tryParse('0,0,1,0,1,1,0,NaN'), isNull);      // NaN token
    expect(CropCorners.tryParse('0,0,1,0,1,1,0,Infinity'), isNull); // inf token
  });

  test('value equality', () {
    expect(CropCorners.fullFrame, CropCorners.fullFrame);
    expect(
      const CropCorners(topLeft: Offset(0, 0), topRight: Offset(1, 0),
          bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1)),
      CropCorners.fullFrame,
    );
    expect(
      const CropCorners(topLeft: Offset(0.5, 0), topRight: Offset(1, 0),
          bottomRight: Offset(1, 1), bottomLeft: Offset(0, 1)),
      isNot(CropCorners.fullFrame),
    );
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/crop_corners_test.dart`
Expected: FAIL — `crop_corners.dart` / `CropCorners` undefined.

- [ ] **Step 3: Write the implementation**

Create `apps/mobile/lib/features/library/crop_corners.dart`:

```dart
import 'package:flutter/painting.dart';

/// Four crop corners of one page, normalized to `[0..1]` in the DISPLAY
/// (EXIF-applied) frame, top-left origin. Role-tagged (not a list): dragging
/// never reassigns which corner is which. Persisted as page metadata (E1);
/// E2 perspective-flattens from these; E3 re-edits. Pure — no widgets.
class CropCorners {
  final Offset topLeft, topRight, bottomRight, bottomLeft;
  const CropCorners({
    required this.topLeft,
    required this.topRight,
    required this.bottomRight,
    required this.bottomLeft,
  });

  /// The whole image, uncropped — the default and the meaning of a null/legacy
  /// stored value.
  static const CropCorners fullFrame = CropCorners(
    topLeft: Offset(0, 0),
    topRight: Offset(1, 0),
    bottomRight: Offset(1, 1),
    bottomLeft: Offset(0, 1),
  );

  /// Each corner pulled into `[0,1]x[0,1]`.
  CropCorners clamp() => CropCorners(
        topLeft: _clamp(topLeft),
        topRight: _clamp(topRight),
        bottomRight: _clamp(bottomRight),
        bottomLeft: _clamp(bottomLeft),
      );

  /// `"x0,y0,x1,y1,x2,y2,x3,y3"` in role order TL,TR,BR,BL, fixed precision.
  String toStorage() => [
        topLeft.dx, topLeft.dy,
        topRight.dx, topRight.dy,
        bottomRight.dx, bottomRight.dy,
        bottomLeft.dx, bottomLeft.dy,
      ].map((d) => d.toStringAsFixed(6)).join(',');

  /// Fail-soft: returns null on null / empty / wrong count / non-numeric /
  /// non-finite (NaN/Infinity). NEVER throws — a bad stored value must not
  /// brick the list or viewer.
  static CropCorners? tryParse(String? s) {
    if (s == null || s.isEmpty) return null;
    final parts = s.split(',');
    if (parts.length != 8) return null;
    final v = <double>[];
    for (final p in parts) {
      final d = double.tryParse(p);
      if (d == null || !d.isFinite) return null;
      v.add(d);
    }
    return CropCorners(
      topLeft: Offset(v[0], v[1]),
      topRight: Offset(v[2], v[3]),
      bottomRight: Offset(v[4], v[5]),
      bottomLeft: Offset(v[6], v[7]),
    );
  }

  static Offset _clamp(Offset o) =>
      Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));

  @override
  bool operator ==(Object other) =>
      other is CropCorners &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => 'CropCorners($topLeft, $topRight, $bottomRight, $bottomLeft)';
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/library/crop_corners_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/library/crop_corners.dart \
        apps/mobile/test/features/library/crop_corners_test.dart
git commit -m "feat(e1): CropCorners model (normalized, role-tagged, fail-soft serialization)"
```

---

### Task 2: Schema migration (Pages.corners, v1→v2) + migration test

**Files:**
- Modify: `apps/mobile/lib/features/library/drift/app_database.dart`
- Modify: `apps/mobile/pubspec.yaml` (dev_dependencies: `sqlite3`)
- Test: `apps/mobile/test/features/library/drift/migration_test.dart`

**Interfaces:**
- Produces: `Pages` table gains a nullable `corners` text column; `AppDatabase.schemaVersion == 2`; opening a v1 DB triggers `onUpgrade` adding the column.

- [ ] **Step 1: Add the column + bump version + onUpgrade**

In `apps/mobile/lib/features/library/drift/app_database.dart`, add to the `Pages` table (after `relativeImagePath`):

```dart
  /// Normalized crop quad (E1) as "x0,y0,...,x3,y3"; null = uncropped (full
  /// frame). See CropCorners.
  TextColumn get corners => text().nullable()();
```

Change `schemaVersion` and `migration`:

```dart
  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(pages, pages.corners);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
```

NOTE: inside `AppDatabase` the tables are the generated accessors `pages`/`documents` (the migration closure captures `this`) — that is why it is `pages, pages.corners` and NOT `_db.pages`.

- [ ] **Step 2: Regenerate Drift code**

Run: `cd apps/mobile && dart run build_runner build`
Expected: marker `Built with build_runner`; `app_database.g.dart` now includes the `corners` column on `Pages`.

- [ ] **Step 3: Add the test-only `sqlite3` dev dependency**

In `apps/mobile/pubspec.yaml` under `dev_dependencies:`, add:

```yaml
  sqlite3: ^2.4.0
```

Run: `cd apps/mobile && flutter pub get`
Expected: resolves (already transitive via drift). This is TEST-ONLY (migration v1 setup); no runtime/privacy dependency is added.

- [ ] **Step 4: Write the failing migration test**

Create `apps/mobile/test/features/library/drift/migration_test.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('upgrading a v1 database adds the nullable Pages.corners column', () async {
    final dir = await Directory.systemTemp.createTemp('e1mig');
    final file = File('${dir.path}/app.db');

    // 1) Build a v1-shaped DB by raw SQL (pages WITHOUT corners), version 1.
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('''
      CREATE TABLE documents (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        created_at TEXT NOT NULL,
        modified_at TEXT NOT NULL
      );
    ''');
    raw.execute('''
      CREATE TABLE pages (
        id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
        document_id INTEGER NOT NULL REFERENCES documents (id) ON DELETE CASCADE,
        position INTEGER NOT NULL,
        relative_image_path TEXT NOT NULL
      );
    ''');
    raw.execute("INSERT INTO documents (id, name, created_at, modified_at) "
        "VALUES (1, 'Scan old', '2026-01-01T00:00:00.000Z', '2026-01-01T00:00:00.000Z');");
    raw.execute("INSERT INTO pages (id, document_id, position, relative_image_path) "
        "VALUES (1, 1, 1, '1/1.jpg');");
    raw.execute('PRAGMA user_version = 1;');
    raw.dispose();

    // 2) Open the real (v2) AppDatabase on the same file -> triggers onUpgrade.
    final db = AppDatabase(NativeDatabase(file));

    // 3a) The corners column exists and the legacy row reads back null.
    final rows = await db.select(db.pages).get();
    expect(rows, hasLength(1));
    expect(rows.single.corners, isNull);
    expect(CropCorners.tryParse(rows.single.corners) ?? CropCorners.fullFrame,
        CropCorners.fullFrame);

    // 3b) A fresh corners write round-trips.
    await (db.update(db.pages)..where((t) => t.id.equals(1)))
        .write(PagesCompanion(corners: Value(CropCorners.fullFrame.toStorage())));
    final updated = await (db.select(db.pages)..where((t) => t.id.equals(1))).getSingle();
    expect(CropCorners.tryParse(updated.corners), CropCorners.fullFrame);

    await db.close();
    await dir.delete(recursive: true);
  });
}
```

- [ ] **Step 5: Run the migration test**

Run: `cd apps/mobile && flutter test test/features/library/drift/migration_test.dart`
Expected: PASS (the v1 DB upgrades; legacy row reads null→fullFrame; fresh write round-trips).

- [ ] **Step 6: Run the full suite + analyze**

Run: `pnpm nx run mobile:test --skip-nx-cache` → `All tests passed!`
Run: `pnpm nx run mobile:analyze --skip-nx-cache` → `Successfully ran target analyze`
(Existing repo tests still pass — the new column is nullable and unused by them yet.)

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/library/drift/app_database.dart \
        apps/mobile/lib/features/library/drift/app_database.g.dart \
        apps/mobile/pubspec.yaml apps/mobile/pubspec.lock \
        apps/mobile/test/features/library/drift/migration_test.dart
git commit -m "feat(e1): Pages.corners column + schemaVersion 1->2 migration (tested)"
```

---

### Task 3: Persist & read corners (repo + PageImage + Fake)

**Files:**
- Modify: `apps/mobile/lib/features/library/page_image.dart`
- Modify: `apps/mobile/lib/features/library/document_repository.dart`
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes: `CropCorners` (Task 1), `Pages.corners` (Task 2).
- Produces: `PageImage` gains `final CropCorners corners` (default `fullFrame`); `DocumentRepository.createFromCapture(CapturedImage capture, {CropCorners? corners})`; `FakeDocumentRepository` records `lastSavedCorners`.

- [ ] **Step 1: Write the failing repo round-trip tests**

This file already has (verified): a synchronous `DriftDocumentRepository repo({ImageMetadataScrubber? scrubber})` helper bound to a shared in-memory `db` + temp `base`, and a top-level `late CapturedImage capture` built in `setUp` from `test/fixtures/exif_sample.jpg`. Reuse them — do NOT invent `sampleCapture()` and note `repo()` is **synchronous** (no `await`). Add the imports `import 'package:flutter/painting.dart';` (for `Offset`) and `import 'package:mobile/features/library/crop_corners.dart';` at the top. Append inside `main()`:

```dart
  test('createFromCapture persists the given corners; getDocumentPages reads them back',
      () async {
    const corners = CropCorners(
      topLeft: Offset(0.1, 0.1), topRight: Offset(0.9, 0.12),
      bottomRight: Offset(0.88, 0.9), bottomLeft: Offset(0.08, 0.92));
    final doc = await repo().createFromCapture(capture, corners: corners);
    final pages = await repo().getDocumentPages(doc.id);
    expect(pages.single.corners, corners);
  });

  test('createFromCapture with no corners reads back fullFrame', () async {
    final doc = await repo().createFromCapture(capture);
    final pages = await repo().getDocumentPages(doc.id);
    expect(pages.single.corners, CropCorners.fullFrame);
  });
```

(`repo()` returns a repository bound to the same shared `db`/`base`, so calling it twice in one test reads/writes the same database.)

- [ ] **Step 2: Run to verify they fail**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart`
Expected: FAIL — `corners` named param undefined on `createFromCapture`; `PageImage.corners` undefined.

- [ ] **Step 3: Add `corners` to `PageImage`**

In `apps/mobile/lib/features/library/page_image.dart`:

```dart
import 'crop_corners.dart';

/// One page's resolved image for the viewer. [imagePath] is ABSOLUTE (resolved
/// at read time via DocumentFileStore). [corners] is the page's crop quad
/// (full-frame when uncropped). Symmetric with DocumentSummary on the read side.
class PageImage {
  final int position;
  final String imagePath;
  final CropCorners corners;
  const PageImage({
    required this.position,
    required this.imagePath,
    this.corners = CropCorners.fullFrame,
  });
}
```

- [ ] **Step 4: Add the optional `corners` param to the interface**

In `apps/mobile/lib/features/library/document_repository.dart`, add the import and change the signature + doc:

```dart
import 'crop_corners.dart';
```
```dart
  /// Persists [capture] (EXIF-scrubbed) and creates a one-page document with the
  /// page's crop [corners] (defaults to full-frame). Image bytes are NOT
  /// transformed — corners are metadata (E1). Throws [DocumentSaveException] on
  /// failure (the capture is not lost).
  Future<Document> createFromCapture(CapturedImage capture, {CropCorners? corners});
```

- [ ] **Step 5: Write/read corners in the Drift repo**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`:

Add `import '../crop_corners.dart';`. Change the signature:
```dart
  @override
  Future<Document> createFromCapture(CapturedImage capture, {CropCorners? corners}) async {
```
In the page insert, add the corners value:
```dart
        await _db.into(_db.pages).insert(
              PagesCompanion.insert(
                  documentId: docId,
                  position: 1,
                  relativeImagePath: rel,
                  corners: Value(corners?.toStorage())),
            );
```
In `getDocumentPages`, map corners:
```dart
    return pages
        .map((pg) => PageImage(
              position: pg.position,
              imagePath: _fileStore.absoluteFor(pg.relativeImagePath).path,
              corners: CropCorners.tryParse(pg.corners) ?? CropCorners.fullFrame,
            ))
        .toList();
```

- [ ] **Step 6: Update the Fake**

In `apps/mobile/test/support/fake_library.dart`: add `import 'package:mobile/features/library/crop_corners.dart';`; add a field `CropCorners? lastSavedCorners;`; change `createFromCapture`:
```dart
  @override
  Future<Document> createFromCapture(CapturedImage capture, {CropCorners? corners}) async {
    createCalls++;
    lastSavedCorners = corners;
    if (gate != null) await gate!.future;
    if (throwOnCreate) {
      throw const DocumentSaveException('fake: save failed');
    }
    final doc = Document(
      id: documents.length + 1,
      name: 'Scan 2026-06-27 20.26.42',
      createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    );
    documents.insert(0, doc);
    return doc;
  }
```
The Fake's `getDocumentPages` returns `PageImage(position:1, imagePath:...)` — unchanged (the default `corners: fullFrame` applies). `_FlakyPagesRepo` in `page_viewer_screen_test.dart` likewise needs no change (default applies).

- [ ] **Step 7: Run the repo tests + full suite + analyze**

Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart` → PASS.
Run: `pnpm nx run mobile:test --skip-nx-cache` → `All tests passed!` (existing B3 viewer / C1 PDF tests still green — they read only `imagePath`).
Run: `pnpm nx run mobile:analyze --skip-nx-cache` → `Successfully ran target analyze`.

- [ ] **Step 8: Commit**

```bash
git add apps/mobile/lib/features/library/page_image.dart \
        apps/mobile/lib/features/library/document_repository.dart \
        apps/mobile/lib/features/library/drift/drift_document_repository.dart \
        apps/mobile/test/support/fake_library.dart \
        apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(e1): persist + read per-page crop corners (repo, PageImage, fake)"
```

---

### Task 4: `CropOverlay` widget

**Files:**
- Create: `apps/mobile/lib/features/scan/widgets/crop_overlay.dart`
- Test: `apps/mobile/test/features/scan/widgets/crop_overlay_test.dart`

**Interfaces:**
- Consumes: `CropCorners` (Task 1).
- Produces: `class CropOverlay extends StatelessWidget` with `Size imageSize`, `Widget image`, `CropCorners corners`, `ValueChanged<CropCorners> onCornersChanged`, `bool enabled = true`. Keys: `crop-overlay`, `crop-handle-tl`/`-tr`/`-br`/`-bl`.

- [ ] **Step 1: Write the failing tests**

Create `apps/mobile/test/features/scan/widgets/crop_overlay_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

void main() {
  // 400x300 box; image 1000x750 (same 4:3 aspect) => contain rect fills the box
  // exactly: rect = (0,0) 400x300. So normalized (nx,ny) -> (nx*400, ny*300).
  Future<CropCorners?> pump(WidgetTester tester,
      {CropCorners corners = CropCorners.fullFrame, bool enabled = true}) async {
    CropCorners? last;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: corners,
              enabled: enabled,
              onCornersChanged: (c) => last = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return last == null ? null : last;
  }

  testWidgets('renders the overlay and four handles by key', (tester) async {
    await pump(tester);
    expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
    for (final k in ['crop-handle-tl', 'crop-handle-tr', 'crop-handle-br', 'crop-handle-bl']) {
      expect(find.byKey(Key(k)), findsOneWidget);
    }
  });

  testWidgets('handles sit at the fitted-rect corners for full frame', (tester) async {
    await pump(tester);
    expect(tester.getCenter(find.byKey(const Key('crop-handle-tl'))),
        offsetMoreOrLessEquals(tester.getTopLeft(find.byKey(const Key('crop-overlay'))),
            epsilon: 1.0));
  });

  testWidgets('dragging top-left emits a clamped normalized corner', (tester) async {
    CropCorners? out;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: CropCorners.fullFrame,
              onCornersChanged: (c) => out = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    // 40/400 = 0.1 ; 30/300 = 0.1
    expect(out, isNotNull);
    expect(out!.topLeft.dx, moreOrLessEquals(0.1, epsilon: 0.01));
    expect(out!.topLeft.dy, moreOrLessEquals(0.1, epsilon: 0.01));
  });

  testWidgets('dragging past the edge clamps to 0', (tester) async {
    CropCorners? out;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: CropCorners.fullFrame,
              onCornersChanged: (c) => out = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(-80, -80));
    await tester.pumpAndSettle();
    expect(out!.topLeft, const Offset(0, 0));
  });

  testWidgets('empty imageSize renders no handles', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 400, height: 300,
          child: CropOverlay(
            imageSize: Size.zero,
            image: ColoredBox(color: Colors.black),
            corners: CropCorners.fullFrame,
            onCornersChanged: _noop,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-handle-tl')), findsNothing);
  });

  testWidgets('disabled overlay ignores drags', (tester) async {
    // NOTE: capture the callback ACROSS the drag (do not use pump()'s return,
    // which snapshots before the drag and would make this assertion vacuous).
    CropCorners? out;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400, height: 300,
            child: CropOverlay(
              imageSize: const Size(1000, 750),
              image: const ColoredBox(color: Colors.black),
              corners: CropCorners.fullFrame,
              enabled: false,
              onCornersChanged: (c) => out = c,
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    expect(out, isNull); // disabled => onCornersChanged never fired during the drag
  });

  testWidgets('handles carry semantic labels', (tester) async {
    await pump(tester);
    expect(find.bySemanticsLabel('Top-left crop corner'), findsOneWidget);
    expect(find.bySemanticsLabel('Bottom-right crop corner'), findsOneWidget);
  });
}

void _noop(CropCorners _) {}
```

- [ ] **Step 2: Run to verify they fail**

Run: `cd apps/mobile && flutter test test/features/scan/widgets/crop_overlay_test.dart`
Expected: FAIL — `crop_overlay.dart` / `CropOverlay` undefined.

- [ ] **Step 3: Write the implementation**

Create `apps/mobile/lib/features/scan/widgets/crop_overlay.dart`:

```dart
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../library/crop_corners.dart';

/// Draggable 4-corner crop overlay drawn over a captured image (E1). Controlled:
/// the parent owns the [corners] state. Renders the injected [image] in the
/// BoxFit.contain rect and places handles in that same rect, so they align by
/// construction. Drag is delta-based and clamps each corner to image bounds
/// (topology is NOT enforced — E2 guards degenerate quads). [imageSize] is the
/// EXIF-applied natural size, injected so this widget needs no image decode.
class CropOverlay extends StatelessWidget {
  final Size imageSize;
  final Widget image;
  final CropCorners corners;
  final ValueChanged<CropCorners> onCornersChanged;
  final bool enabled;
  const CropOverlay({
    super.key,
    required this.imageSize,
    required this.image,
    required this.corners,
    required this.onCornersChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      key: const Key('crop-overlay'),
      builder: (context, constraints) {
        if (imageSize.width <= 0 || imageSize.height <= 0) {
          return image; // degenerate size: show the image, no handles
        }
        final box = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = math.min(box.width / imageSize.width,
            box.height / imageSize.height);
        final display = imageSize * scale;
        final rect = Offset((box.width - display.width) / 2,
                (box.height - display.height) / 2) &
            display;

        Offset posOf(Offset n) =>
            rect.topLeft + Offset(n.dx * rect.width, n.dy * rect.height);

        void dragBy(String role, Offset delta) {
          if (!enabled) return;
          final dNorm = Offset(delta.dx / rect.width, delta.dy / rect.height);
          Offset clamp01(Offset o) =>
              Offset(o.dx.clamp(0.0, 1.0), o.dy.clamp(0.0, 1.0));
          switch (role) {
            case 'tl':
              onCornersChanged(CropCorners(
                  topLeft: clamp01(corners.topLeft + dNorm),
                  topRight: corners.topRight,
                  bottomRight: corners.bottomRight,
                  bottomLeft: corners.bottomLeft));
            case 'tr':
              onCornersChanged(CropCorners(
                  topLeft: corners.topLeft,
                  topRight: clamp01(corners.topRight + dNorm),
                  bottomRight: corners.bottomRight,
                  bottomLeft: corners.bottomLeft));
            case 'br':
              onCornersChanged(CropCorners(
                  topLeft: corners.topLeft,
                  topRight: corners.topRight,
                  bottomRight: clamp01(corners.bottomRight + dNorm),
                  bottomLeft: corners.bottomLeft));
            case 'bl':
              onCornersChanged(CropCorners(
                  topLeft: corners.topLeft,
                  topRight: corners.topRight,
                  bottomRight: corners.bottomRight,
                  bottomLeft: clamp01(corners.bottomLeft + dNorm)));
          }
        }

        return Stack(
          children: [
            Positioned.fromRect(rect: rect, child: image),
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _QuadPainter(rect: rect, corners: corners),
                ),
              ),
            ),
            _handle('tl', 'Top-left crop corner', posOf(corners.topLeft), dragBy),
            _handle('tr', 'Top-right crop corner', posOf(corners.topRight), dragBy),
            _handle('br', 'Bottom-right crop corner', posOf(corners.bottomRight), dragBy),
            _handle('bl', 'Bottom-left crop corner', posOf(corners.bottomLeft), dragBy),
          ],
        );
      },
    );
  }

  Widget _handle(String role, String label, Offset center,
      void Function(String, Offset) dragBy) {
    const r = 22.0; // touch radius
    return Positioned(
      left: center.dx - r,
      top: center.dy - r,
      child: Semantics(
        label: label,
        child: GestureDetector(
          key: Key('crop-handle-$role'),
          onPanUpdate: enabled ? (d) => dragBy(role, d.delta) : null,
          child: Container(
            width: r * 2,
            height: r * 2,
            alignment: Alignment.center,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.blue, width: 2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _QuadPainter extends CustomPainter {
  final Rect rect;
  final CropCorners corners;
  _QuadPainter({required this.rect, required this.corners});

  Offset _p(Offset n) =>
      rect.topLeft + Offset(n.dx * rect.width, n.dy * rect.height);

  @override
  void paint(Canvas canvas, Size size) {
    final quad = Path()
      ..moveTo(_p(corners.topLeft).dx, _p(corners.topLeft).dy)
      ..lineTo(_p(corners.topRight).dx, _p(corners.topRight).dy)
      ..lineTo(_p(corners.bottomRight).dx, _p(corners.bottomRight).dy)
      ..lineTo(_p(corners.bottomLeft).dx, _p(corners.bottomLeft).dy)
      ..close();
    // Dim outside the quad.
    final outside = Path.combine(PathOperation.difference,
        Path()..addRect(Offset.zero & size), quad);
    canvas.drawPath(outside, Paint()..color = Colors.black54);
    // Quad outline.
    canvas.drawPath(
        quad,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = Colors.blue);
  }

  @override
  bool shouldRepaint(_QuadPainter old) =>
      old.rect != rect || old.corners != corners;
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `cd apps/mobile && flutter test test/features/scan/widgets/crop_overlay_test.dart`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add apps/mobile/lib/features/scan/widgets/crop_overlay.dart \
        apps/mobile/test/features/scan/widgets/crop_overlay_test.dart
git commit -m "feat(e1): CropOverlay widget (fitted-rect handles, clamped delta drag, a11y)"
```

---

### Task 5: Wire overlay into the Review flow

**Files:**
- Modify: `apps/mobile/lib/features/scan/capture_review_screen.dart` (→ StatefulWidget)
- Modify: `apps/mobile/lib/features/library/save_controller.dart`
- Modify: `apps/mobile/lib/features/scan/camera_screen.dart`
- Test: `apps/mobile/test/features/scan/capture_review_screen_test.dart` (migrate + extend)

**Interfaces:**
- Consumes: `CropCorners` (T1), `CropOverlay` (T4), `createFromCapture({corners})` (T3).
- Produces: `CaptureReviewScreen.onAccept` is now `ValueChanged<CropCorners>`; `SaveController.save(image, {CropCorners corners = CropCorners.fullFrame})`.

- [ ] **Step 1: Migrate existing review tests to the new `onAccept` signature**

In `apps/mobile/test/features/scan/capture_review_screen_test.dart`, change every `onAccept: () {...}` / `onAccept: someVoidCallback` to `onAccept: (corners) {...}` (accept the `CropCorners` arg; ignore it where the test doesn't care). This is required for compilation under the new signature. Do NOT change unrelated assertions.

- [ ] **Step 2: Write the failing new review tests**

Append to `apps/mobile/test/features/scan/capture_review_screen_test.dart` (inside `main()`). Use a NON-LOADABLE image path so `Image.file` shows its error builder without hanging:

```dart
  CaptureReviewScreen subject({
    required ValueChanged<CropCorners> onAccept,
    VoidCallback? onRetake,
    bool saving = false,
    Future<Size> Function(String)? decode,
  }) =>
      CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/cap.jpg'),
        onRetake: onRetake ?? () {},
        onAccept: onAccept,
        saving: saving,
        decodeImageSize: decode ?? (_) async => const Size(1000, 750),
      );

  testWidgets('shows the crop overlay once the size resolves', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (_) {})));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
  });

  testWidgets('shows the plain image (no overlay) before the size resolves',
      (tester) async {
    final never = Completer<Size>();
    await tester.pumpWidget(MaterialApp(
        home: subject(onAccept: (_) {}, decode: (_) => never.future)));
    await tester.pump(); // do not settle (would hang on the pending future)
    expect(find.byKey(const Key('review-image')), findsOneWidget);
    expect(find.byKey(const Key('crop-overlay')), findsNothing);
  });

  testWidgets('Accept passes the current corners', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (c) => accepted = c)));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, isNotNull);
    expect(accepted!.topLeft.dx, greaterThan(0.0)); // moved from full-frame
  });

  testWidgets('Reset restores full-frame corners', (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (c) => accepted = c)));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(40, 30));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('crop-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
  });

  testWidgets('saving disables the overlay and Reset', (tester) async {
    await tester.pumpWidget(MaterialApp(home: subject(onAccept: (_) {}, saving: true)));
    await tester.pumpAndSettle();
    final reset = tester.widget<TextButton>(find.byKey(const Key('crop-reset')));
    expect(reset.onPressed, isNull);
  });

  testWidgets('decode failure falls back to the plain image; Accept still works',
      (tester) async {
    CropCorners? accepted;
    await tester.pumpWidget(MaterialApp(
        home: subject(onAccept: (c) => accepted = c, decode: (_) async => throw 'boom')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('crop-overlay')), findsNothing);
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(accepted, CropCorners.fullFrame);
  });

  testWidgets('popping before the size resolves does not setState after dispose',
      (tester) async {
    final later = Completer<Size>();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: Builder(builder: (ctx) => ElevatedButton(
          onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
              builder: (_) => subject(onAccept: (_) {}, decode: (_) => later.future))),
          child: const Text('open'))),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pump();
    nav.currentState!.pop();          // leave the review screen
    await tester.pumpAndSettle();
    later.complete(const Size(1000, 750)); // resolver lands after dispose
    await tester.pump();
    expect(tester.takeException(), isNull); // no setState-after-dispose
  });
```

Add imports at the top if missing: `dart:async` (Completer), `package:mobile/features/library/crop_corners.dart`, `package:mobile/features/scan/captured_image.dart`.

- [ ] **Step 3: Run to verify they fail**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_screen_test.dart`
Expected: FAIL — `decodeImageSize` param / `crop-overlay` / `crop-reset` undefined.

- [ ] **Step 4: Rewrite `CaptureReviewScreen` as a StatefulWidget**

Replace `apps/mobile/lib/features/scan/capture_review_screen.dart` with:

```dart
import 'dart:io';

import 'package:flutter/material.dart';

import '../library/crop_corners.dart';
import 'captured_image.dart';
import 'widgets/crop_overlay.dart';

/// Default EXIF-applied natural-size resolver: the framework decoder bakes the
/// Orientation tag, so this size matches the displayed (and stored) image.
Future<Size> _resolveImageSize(String path) {
  final completer = Completer<Size>();
  final stream = FileImage(File(path)).resolve(ImageConfiguration.empty);
  late final ImageStreamListener listener;
  listener = ImageStreamListener((info, _) {
    if (!completer.isCompleted) {
      completer.complete(Size(
          info.image.width.toDouble(), info.image.height.toDouble()));
    }
    stream.removeListener(listener);
  }, onError: (e, st) {
    if (!completer.isCompleted) completer.completeError(e);
    stream.removeListener(listener);
  });
  stream.addListener(listener);
  return completer.future;
}

/// Shows a freshly captured [image] with Retake / Reset / Accept. Once the
/// image's natural size resolves, draws a draggable crop overlay; Accept hands
/// the chosen [CropCorners] up (the parent saves). Saving disables actions.
class CaptureReviewScreen extends StatefulWidget {
  final CapturedImage image;
  final VoidCallback onRetake;
  final ValueChanged<CropCorners> onAccept;
  final bool saving;
  final Future<Size> Function(String path) decodeImageSize;

  const CaptureReviewScreen({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onAccept,
    this.saving = false,
    this.decodeImageSize = _resolveImageSize,
  });

  @override
  State<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends State<CaptureReviewScreen> {
  CropCorners _corners = CropCorners.fullFrame;
  Size? _imageSize;

  @override
  void initState() {
    super.initState();
    widget.decodeImageSize(widget.image.path).then((size) {
      if (!mounted) return;
      setState(() => _imageSize = size);
    }).catchError((_) {/* leave _imageSize null -> plain image */});
  }

  Widget _imageWidget() => Image.file(
        File(widget.image.path),
        key: const Key('review-image'),
        fit: BoxFit.contain,
        errorBuilder: (context, error, stack) => const Icon(
          Icons.broken_image_outlined,
          key: Key('review-image-error'),
          color: Colors.white54,
          size: 64,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final size = _imageSize;
    final canCrop = size != null && !widget.saving;
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Stack(
        children: [
          ColoredBox(
            color: Colors.black,
            child: SizedBox.expand(
              child: size == null
                  ? Center(child: _imageWidget())
                  : CropOverlay(
                      imageSize: size,
                      image: _imageWidget(),
                      corners: _corners,
                      enabled: !widget.saving,
                      onCornersChanged: (c) => setState(() => _corners = c),
                    ),
            ),
          ),
          if (widget.saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                    child: CircularProgressIndicator(key: Key('review-saving'))),
              ),
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              OutlinedButton.icon(
                key: const Key('review-retake'),
                onPressed: widget.saving ? null : widget.onRetake,
                icon: const Icon(Icons.replay),
                label: const Text('Retake'),
              ),
              TextButton(
                key: const Key('crop-reset'),
                onPressed: canCrop
                    ? () => setState(() => _corners = CropCorners.fullFrame)
                    : null,
                child: const Text('Reset'),
              ),
              FilledButton.icon(
                key: const Key('review-accept'),
                onPressed: widget.saving ? null : () => widget.onAccept(_corners),
                icon: const Icon(Icons.check),
                label: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Add `import 'dart:async';` at the top (Completer).

- [ ] **Step 5: Thread corners through `SaveController` and `camera_screen`**

In `apps/mobile/lib/features/library/save_controller.dart`: add `import 'crop_corners.dart';`; change `save`:
```dart
  Future<Document?> save(CapturedImage image,
      {CropCorners corners = CropCorners.fullFrame}) async {
    if (_disposed || _status == SaveStatus.saving) return null;
    _set(SaveStatus.saving);
    try {
      final doc = await _repository.createFromCapture(image, corners: corners);
      if (_disposed) return null;
      _set(SaveStatus.idle);
      return doc;
    } catch (_) {
      if (_disposed) return null;
      _set(SaveStatus.error);
      return null;
    }
  }
```

In `apps/mobile/lib/features/scan/camera_screen.dart`: add `import '../library/crop_corners.dart';`; change the review builder and `_onAccept`:
```dart
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            saving: _saveController.saving,
            onRetake: navigator.pop,
            onAccept: (corners) => _onAccept(image, corners),
          ),
```
```dart
  Future<void> _onAccept(CapturedImage image, CropCorners corners) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final doc = await _saveController.save(image, corners: corners);
    if (!mounted) return;
    if (doc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't save document. Try again.")),
      );
      return;
    }
    navigator.popUntil((route) => route.isFirst);
  }
```

- [ ] **Step 6: Run the review tests + full suite + analyze**

Run: `cd apps/mobile && flutter test test/features/scan/capture_review_screen_test.dart` → PASS.
Run: `pnpm nx run mobile:test --skip-nx-cache` → `All tests passed!` (existing camera/save tests now compile under the new signatures).
Run: `pnpm nx run mobile:analyze --skip-nx-cache` → `Successfully ran target analyze`.

- [ ] **Step 7: Commit**

```bash
git add apps/mobile/lib/features/scan/capture_review_screen.dart \
        apps/mobile/lib/features/library/save_controller.dart \
        apps/mobile/lib/features/scan/camera_screen.dart \
        apps/mobile/test/features/scan/capture_review_screen_test.dart
git commit -m "feat(e1): host crop overlay on the review screen; carry corners to save"
```

---

### Task 6: BDD integration (wiring smoke test)

**Files:**
- Create: `apps/mobile/integration_test/e1_crop.feature`
- Create: `apps/mobile/test/step/i_see_the_crop_overlay.dart`
- Create: `apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart`
- Generated: `apps/mobile/integration_test/e1_crop_test.dart`

**Interfaces:**
- Consumes: keys `crop-overlay`, `crop-handle-tl` (T4/T5); existing steps `the_app_is_launched_with_camera_permission_granted_and_empty_storage`, `i_tap_the_scan_button`, `i_tap_the_shutter`, `i_tap_accept`, `i_see_a_saved_document_on_the_home`.
- Produces: `iSeeTheCropOverlay(WidgetTester)`, `iDragTheTopLeftCropCorner(WidgetTester)`; generated test calling both + the reused steps.

- [ ] **Step 1: Write the feature**

Create `apps/mobile/integration_test/e1_crop.feature`:

```gherkin
Feature: Adjust crop corners
  Scenario: Drag a corner before saving
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I see the crop overlay
    And I drag the top left crop corner
    And I tap Accept
    Then I see a saved document on the home
```

- [ ] **Step 2: Write the two step files**

Create `apps/mobile/test/step/i_see_the_crop_overlay.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the crop overlay
Future<void> iSeeTheCropOverlay(WidgetTester tester) async {
  await tester.pumpAndSettle(); // wait for the natural-size decode
  expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
}
```

Create `apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I drag the top left crop corner
Future<void> iDragTheTopLeftCropCorner(WidgetTester tester) async {
  await tester.drag(find.byKey(const Key('crop-handle-tl')), const Offset(20, 20));
  await tester.pumpAndSettle();
}
```

- [ ] **Step 3: Generate the test**

Run: `cd apps/mobile && dart run build_runner build`
Expected: `e1_crop_test.dart` created. Verify (no silent stubs):
```bash
grep -n "iSeeTheCropOverlay(tester" apps/mobile/integration_test/e1_crop_test.dart
grep -n "iDragTheTopLeftCropCorner(tester" apps/mobile/integration_test/e1_crop_test.dart
grep -n "iSeeASavedDocumentOnTheHome(tester" apps/mobile/integration_test/e1_crop_test.dart
```
Expected: all three match.

- [ ] **Step 4: (If a device is attached) run the integration test**

Run: `cd apps/mobile && flutter test integration_test/e1_crop_test.dart`
Expected: `All tests passed!`. If no device here, the device lane runs under `scripts/verify/e1.sh` (Task 7) / the controller gate.

- [ ] **Step 5: Commit (include the generated file)**

```bash
git add apps/mobile/integration_test/e1_crop.feature \
        apps/mobile/integration_test/e1_crop_test.dart \
        apps/mobile/test/step/i_see_the_crop_overlay.dart \
        apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart
git commit -m "test(e1): BDD crop-overlay wiring smoke test + step defs"
```

---

### Task 7: Verify gate `scripts/verify/e1.sh`

**Files:**
- Create: `scripts/verify/e1.sh`

**Interfaces:**
- Consumes: `scripts/verify/lib.sh` helpers; all E1 artifacts.

- [ ] **Step 1: Write the verify script**

Create `scripts/verify/e1.sh` (modeled on `scripts/verify/d3.sh`):

```bash
#!/usr/bin/env bash
# Verify E1 (corner overlay) acceptance criteria.
# Run: bash scripts/verify/e1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the Tier-3 lane (drag corners on a physical device — manual).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== E1 verification =="

require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence: CropCorners model ----
assert_file_has "CropCorners class" \
  "apps/mobile/lib/features/library/crop_corners.dart" "class CropCorners"
assert_file_has "CropCorners.fullFrame" \
  "apps/mobile/lib/features/library/crop_corners.dart" "fullFrame"
assert_file_has "CropCorners.toStorage" \
  "apps/mobile/lib/features/library/crop_corners.dart" "toStorage"
assert_file_has "CropCorners.tryParse" \
  "apps/mobile/lib/features/library/crop_corners.dart" "tryParse"

# ---- Schema migration ----
assert_file_has "schemaVersion bumped to 2" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 2;"
assert_file_has "Pages.corners column" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "get corners =>"
assert_file_has "onUpgrade addColumn" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "addColumn"

# ---- Overlay + keys + a11y ----
assert_file_has "CropOverlay class" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "class CropOverlay"
assert_file_has "overlay key" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "crop-overlay"
assert_file_has "handle tl key" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "crop-handle-"
assert_file_has "overlay handles are a11y-labeled" \
  "apps/mobile/lib/features/scan/widgets/crop_overlay.dart" "Semantics"

# ---- Review wiring ----
assert_file_has "review hosts the overlay" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" "CropOverlay("
assert_file_has "review reset control" \
  "apps/mobile/lib/features/scan/capture_review_screen.dart" "crop-reset"

# ---- Persistence wiring ----
assert_file_has "createFromCapture takes corners" \
  "apps/mobile/lib/features/library/document_repository.dart" "createFromCapture(CapturedImage capture, {CropCorners? corners})"
assert_file_has "PageImage carries corners" \
  "apps/mobile/lib/features/library/page_image.dart" "corners"

# ---- Privacy + E2 orientation contract ----
assert_file_has "scrubber re-emits Orientation (E2 frame contract)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "Orientation"
assert_file_has "scrubber is still byte-level (privacy regression)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"

# ---- No-empty-stub guard ----
assert_file_has "step: see-overlay is real (not a stub)" \
  "apps/mobile/test/step/i_see_the_crop_overlay.dart" "crop-overlay"
assert_file_has "step: drag-corner is real (not a stub)" \
  "apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart" "crop-handle-tl"
assert_file_has "step: drag-corner actually drags" \
  "apps/mobile/test/step/i_drag_the_top_left_crop_corner.dart" "drag"
assert_file_has "generated e1 test calls the see-overlay step" \
  "apps/mobile/integration_test/e1_crop_test.dart" "iSeeTheCropOverlay(tester"
assert_file_has "generated e1 test calls the drag step" \
  "apps/mobile/integration_test/e1_crop_test.dart" "iDragTheTopLeftCropCorner(tester"

# ---- Generated code current ----
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff (e1 bdd)" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/e1_crop_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"

# ---- Static criteria ----
assert_cmd "e1 unit + widget + migration tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android e1_crop_test.dart
verify_integration_ios e1_crop_test.dart

# ---- Opt-in REAL_DEVICE Tier-3 ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "REAL_DEVICE Tier-3 (MANUAL): capture a document; confirm 4 corner handles appear, each drags and tracks the finger, the quad/scrim update, Reset restores full frame, and Accept saves the document."
fi

verify_summary
```

- [ ] **Step 2: Make executable + run the static lane**

```bash
chmod +x scripts/verify/e1.sh
VERIFY_SKIP_DEVICE=1 bash scripts/verify/e1.sh
```
Expected: all static asserts PASS, then a single FAIL for the skipped device lane (fail-closed) → `GATE: FAIL`. Confirms wiring without a device.

- [ ] **Step 3: Commit**

```bash
git add scripts/verify/e1.sh
git commit -m "test(e1): verify gate (static asserts + both-platform integration, fail-closed)"
```

---

## Self-Review

**1. Spec coverage** — every spec section maps to a task:
- `CropCorners` model + serialization (Components §1) → Task 1.
- Schema migration 1→2 + migration test (Components §8, Testing) → Task 2.
- Repo write/read + `PageImage` + Fake (Components §6/§7) → Task 3.
- `CropOverlay` (Components §2) → Task 4.
- Review/camera/save wiring incl. `onAccept` breaking-change migration (Components §3/§4/§5, Gaps 16/17) → Task 5.
- BDD integration (Testing) → Task 6.
- `e1.sh` incl. schemaVersion=2, orientation contract guard, privacy, no-stub, fail-closed (Verification) → Task 7.
- Acceptance criteria 1–9 → covered across Tasks 1–7 (1/2 overlay+drag Tasks 4/5; 3 frame/role Task 1; 4 persist+non-destructive Task 3; 5 migration Task 2; 6 a11y Task 4; 7 privacy Task 7 asserts; 8 E2 contract = Global Constraints + Task 7 orientation assert; 9 TDD/BDD+gate Tasks 1–7).

**2. Placeholder scan** — no TBD/TODO; every code step has complete code; every command states its expected marker. Task 2's `onUpgrade` snippet shows the correct `pages, pages.corners` directly (the migration closure captures `this`); the repo-impl code in Task 3 Step 5 correctly uses the repository's `_db` field — the two contexts are distinct and both shown correctly.

**3. Type consistency** — `CropCorners` (role-tagged fields, `fullFrame`, `toStorage`/`tryParse`), `createFromCapture(CapturedImage, {CropCorners? corners})`, `save(image, {CropCorners corners = CropCorners.fullFrame})`, `PageImage({..., corners = CropCorners.fullFrame})`, `CropOverlay({imageSize, image, corners, onCornersChanged, enabled})`, `onAccept: ValueChanged<CropCorners>`, and keys (`crop-overlay`, `crop-handle-{tl,tr,br,bl}`, `crop-reset`) are used identically across Tasks 1→7. Consistent.
