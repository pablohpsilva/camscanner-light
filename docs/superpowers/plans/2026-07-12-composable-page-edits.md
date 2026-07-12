# Composable, Non-Destructive Page Edits — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make crop, rotate, and retake compose and repeat infinitely by regenerating the displayed image from a pristine, write-once base plus composable transform metadata.

**Architecture:** A page's base file (`Pages.relativeImagePath`) is pristine and never written by an edit. Rotation becomes metadata (`rotationQuarterTurns`, 0–3 CW), crop stays as display-frame `corners`, and one repository helper `_writeFlat` regenerates the `flatRelativePath` derivative from the base by applying rotate-then-crop. All three edit operations route through that single helper.

**Tech Stack:** Flutter, Drift (sqlite) + FTS5, `package:image` (rotate/encode), `HybridWarper` (opencv/coons), `bdd_widget_test`.

## Global Constraints

- TDD + BDD required, verified green on **Android AND iOS** real devices. Evidence (command + result) before claiming done.
- `flutter analyze` zero-warning bar; `dart format lib test` before every commit.
- Run all Flutter commands from `apps/mobile/`.
- **Never persist absolute image paths** — relative only (resolved via `DocumentFileStore`).
- **Scoped `git add` only** — name each path explicitly. NEVER `git add -A`/`.`. The working tree carries a long-lived unrelated WIP pile; `build_runner` regenerates many `*.g.dart`/`*_test.dart` files — add ONLY the files your task changed.
- Corners are normalized `[0..1]` in the **display frame** (image after `rotationQuarterTurns` applied). `CropCorners.fullFrame` means uncropped and is stored as SQL `NULL`.
- Transform order during regeneration is **rotate-then-crop**.
- The base file's bytes must be **byte-for-byte unchanged** by any crop/rotate. Only a new capture (`createFromCapture`/`replacePage`) writes the base.

---

### Task 1: `CropCorners.rotate90Cw()` value helper

**Files:**
- Modify: `lib/features/library/crop_corners.dart` (add a method to the class, before `toString`)
- Test: `test/features/library/crop_corners_rotate_test.dart` (create)

**Interfaces:**
- Consumes: existing `CropCorners` (`Offset topLeft/topRight/bottomRight/bottomLeft`, `topMidDev/rightMidDev/bottomMidDev/leftMidDev`, `static const fullFrame`, value `==`).
- Produces: `CropCorners CropCorners.rotate90Cw()` — the same physical crop quad expressed after the image is rotated 90° clockwise. `fullFrame.rotate90Cw() == fullFrame`; four applications return an equal value.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/library/crop_corners_rotate_test.dart
import 'dart:ui' show Offset;
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';

void main() {
  test('fullFrame is invariant under rotate90Cw', () {
    expect(CropCorners.fullFrame.rotate90Cw(), CropCorners.fullFrame);
  });

  test('four quarter-turns return an equal quad (identity)', () {
    const c = CropCorners(
      topLeft: Offset(0.1, 0.2),
      topRight: Offset(0.8, 0.2),
      bottomRight: Offset(0.8, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    expect(c.rotate90Cw().rotate90Cw().rotate90Cw().rotate90Cw(), c);
  });

  test('rotates a known quad CW (point map + role remap)', () {
    const c = CropCorners(
      topLeft: Offset(0.1, 0.2),
      topRight: Offset(0.8, 0.2),
      bottomRight: Offset(0.8, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    final r = c.rotate90Cw();
    expect(r.topLeft, const Offset(0.1, 0.1));
    expect(r.topRight, const Offset(0.8, 0.1));
    expect(r.bottomRight, const Offset(0.8, 0.8));
    expect(r.bottomLeft, const Offset(0.1, 0.8));
  });

  test('rotates mid-edge deviations with their edges', () {
    const c = CropCorners(
      topLeft: Offset(0.0, 0.0),
      topRight: Offset(1.0, 0.0),
      bottomRight: Offset(1.0, 1.0),
      bottomLeft: Offset(0.0, 1.0),
      topMidDev: Offset(0.0, -0.05), // top edge bulges up
    );
    final r = c.rotate90Cw();
    // old top edge becomes the new RIGHT edge; vector (0,-0.05) -> (0.05, 0)
    expect(r.rightMidDev.dx, closeTo(0.05, 1e-9));
    expect(r.rightMidDev.dy, closeTo(0.0, 1e-9));
    expect(r.topMidDev, Offset.zero);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/crop_corners_rotate_test.dart`
Expected: FAIL — `The method 'rotate90Cw' isn't defined for the type 'CropCorners'`.

- [ ] **Step 3: Add the method**

Insert this method into `class CropCorners` in `lib/features/library/crop_corners.dart`, immediately before the `@override String toString()`:

```dart
  /// This crop quad after the page image is rotated 90° CLOCKWISE, in
  /// normalized coords. Matches `image.copyRotate(angle: 90)` and mirrors
  /// [OcrWordBox.rotate90Cw]: a point `(x, y)` maps to `(1 - y, x)`, and each
  /// role is relabeled to its new visual position so the SAME physical region
  /// is described in the rotated frame. Mid-edge deviations rotate with their
  /// edges (deviation vector `(dx, dy)` maps to `(-dy, dx)`).
  CropCorners rotate90Cw() {
    Offset rot(Offset p) => Offset(1 - p.dy, p.dx);
    Offset rotVec(Offset d) => Offset(-d.dy, d.dx);
    return CropCorners(
      topLeft: rot(bottomLeft),
      topRight: rot(topLeft),
      bottomRight: rot(topRight),
      bottomLeft: rot(bottomRight),
      topMidDev: rotVec(leftMidDev),
      rightMidDev: rotVec(topMidDev),
      bottomMidDev: rotVec(rightMidDev),
      leftMidDev: rotVec(bottomMidDev),
    );
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/crop_corners_rotate_test.dart`
Expected: PASS (4 tests).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/library/crop_corners.dart test/features/library/crop_corners_rotate_test.dart
flutter analyze lib/features/library/crop_corners.dart test/features/library/crop_corners_rotate_test.dart
git add lib/features/library/crop_corners.dart test/features/library/crop_corners_rotate_test.dart
git commit -m "feat(library): CropCorners.rotate90Cw for composable rotation"
```

---

### Task 2: `rotationQuarterTurns` column + schema migration v6→v7

**Files:**
- Modify: `lib/features/library/drift/app_database.dart` (add column to `Pages`, bump `schemaVersion`, add `onUpgrade` step)
- Regenerate: `lib/features/library/drift/app_database.g.dart` (via build_runner — do NOT hand-edit)
- Test: `test/features/library/schema_migration_v7_test.dart` (create)

**Interfaces:**
- Consumes: existing `Pages` table, `AppDatabase`, `MigrationStrategy`.
- Produces: `Pages.rotationQuarterTurns` (`IntColumn`, NOT NULL, DB default `0`). Generated row class exposes `int rotationQuarterTurns`; `PagesCompanion` gains an optional `Value<int> rotationQuarterTurns` (inserts that omit it get `0`). `schemaVersion == 7`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/library/schema_migration_v7_test.dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

void main() {
  test('schemaVersion is 7', () {
    final db = AppDatabase(NativeDatabase.memory());
    expect(db.schemaVersion, 7);
    addTearDown(db.close);
  });

  test('rotationQuarterTurns defaults to 0 on insert without it', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final now = DateTime.now();
    final docId = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    await db.into(db.pages).insert(
          PagesCompanion.insert(
            documentId: docId,
            position: 1,
            relativeImagePath: 'documents/$docId/page_1.jpg',
          ),
        );
    final page = await (db.select(db.pages)
          ..where((t) => t.documentId.equals(docId)))
        .getSingle();
    expect(page.rotationQuarterTurns, 0);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/schema_migration_v7_test.dart`
Expected: FAIL — `schemaVersion` is 6, and `rotationQuarterTurns` getter does not exist.

- [ ] **Step 3: Edit the table + schema**

In `lib/features/library/drift/app_database.dart`, add this column to `class Pages` (after `flatRelativePath`, before `ocrText`):

```dart
  /// Number of 90° clockwise quarter-turns applied to the DISPLAY image (0..3).
  /// Rotation is metadata re-applied during flat regeneration — never baked
  /// destructively into the base image. See DriftDocumentRepository._writeFlat.
  IntColumn get rotationQuarterTurns =>
      integer().withDefault(const Constant(0))();
```

Bump the version:

```dart
  @override
  int get schemaVersion => 7;
```

Add the upgrade step at the end of the `onUpgrade` chain (after the `from < 6` line):

```dart
      if (from < 7) {
        await m.addColumn(pages, pages.rotationQuarterTurns);
      }
```

- [ ] **Step 4: Regenerate drift code**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: completes; `lib/features/library/drift/app_database.g.dart` now has `rotationQuarterTurns`.

- [ ] **Step 5: Run to verify it passes**

Run: `flutter test test/features/library/schema_migration_v7_test.dart`
Expected: PASS (2 tests).

- [ ] **Step 6: Format, analyze, commit (scoped)**

```bash
dart format lib/features/library/drift/app_database.dart test/features/library/schema_migration_v7_test.dart
flutter analyze lib/features/library/drift/
git add lib/features/library/drift/app_database.dart \
        lib/features/library/drift/app_database.g.dart \
        test/features/library/schema_migration_v7_test.dart
git commit -m "feat(library): add Pages.rotationQuarterTurns column (schema v7)"
```
Note: `git status` before committing and confirm NO other `*.g.dart` / generated files were staged. If build_runner regenerated unrelated files, do not stage them.

---

### Task 3: Expose `rotationQuarterTurns` on `PageImage`

**Files:**
- Modify: `lib/features/library/page_image.dart` (add field)
- Modify: `lib/features/library/drift/drift_document_repository.dart` (`getDocumentPages`, ~line 340, populate it)
- Test: `test/features/library/page_rotation_readback_test.dart` (create)

**Interfaces:**
- Consumes: `Pages.rotationQuarterTurns` (Task 2), `getDocumentPages`.
- Produces: `PageImage.rotationQuarterTurns` (`final int`, default `0`), populated from the row. Editor (Task 6) and viewer (Task 7) read it.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/library/page_rotation_readback_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  test('getDocumentPages surfaces rotationQuarterTurns', () async {
    final base = await Directory.systemTemp.createTemp('rot_read');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
    addTearDown(() async {
      await db.close();
      if (await base.exists()) await base.delete(recursive: true);
    });
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(
      rel,
      Uint8List.fromList(img.encodeJpg(img.Image(width: 20, height: 10))),
    );
    await db.into(db.pages).insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
            rotationQuarterTurns: const Value(2),
          ),
        );
    final page = (await repo.getDocumentPages(id)).single;
    expect(page.rotationQuarterTurns, 2);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/page_rotation_readback_test.dart`
Expected: FAIL — `PageImage` has no `rotationQuarterTurns`.

- [ ] **Step 3: Add the field**

In `lib/features/library/page_image.dart`, add the field and constructor param:

```dart
  final int rotationQuarterTurns;
```
and in the constructor add `this.rotationQuarterTurns = 0,` (place it after `this.corners = CropCorners.fullFrame,`).

In `lib/features/library/drift/drift_document_repository.dart` `getDocumentPages`, add to the `PageImage(...)` mapping:

```dart
            rotationQuarterTurns: pg.rotationQuarterTurns,
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/page_rotation_readback_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/library/page_image.dart lib/features/library/drift/drift_document_repository.dart test/features/library/page_rotation_readback_test.dart
flutter analyze lib/features/library/page_image.dart
git add lib/features/library/page_image.dart lib/features/library/drift/drift_document_repository.dart test/features/library/page_rotation_readback_test.dart
git commit -m "feat(library): expose rotationQuarterTurns on PageImage"
```

---

### Task 4: `_writeFlat` regeneration + compose `rotatePage`/`updatePageCorners`

**Files:**
- Modify: `lib/features/library/drift/drift_document_repository.dart` (add `_writeFlat`; rewrite `rotatePage` ~685–736 and `updatePageCorners` ~624–682)
- Test: `test/features/library/composable_edits_test.dart` (create)

**Interfaces:**
- Consumes: `CropCorners.rotate90Cw()` (Task 1), `rotationQuarterTurns` column (Task 2), `DocumentFileStore.flatForImage`, `_warper.warp(Uint8List, CropCorners) → Future<Uint8List?>`, `img` (already imported), `OcrResult.decodeBoxes/encodeBoxes`, `OcrWordBox.rotate90Cw`.
- Produces: private `Future<String?> _writeFlat({required String relativeImagePath, required int quarterTurns, required CropCorners corners, required String? existingFlatRel})`. `rotatePage`/`updatePageCorners` keep their existing public signatures and `DocumentSaveException` behavior.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/library/composable_edits_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Offset;
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

void main() {
  late AppDatabase db;
  late DriftDocumentRepository repo;
  late DocumentFileStore store;
  late Directory base;
  late String baseRel;

  setUp(() async {
    base = await Directory.systemTemp.createTemp('compose');
    db = AppDatabase(NativeDatabase.memory());
    store = DocumentFileStore(base);
    repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
  });
  tearDown(() async {
    await db.close();
    if (await base.exists()) await base.delete(recursive: true);
  });

  Future<int> seed() async {
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    baseRel = 'documents/$id/page_1.jpg';
    // 60x40 landscape so rotation (dims swap) is observable.
    await store.writeRelative(
      baseRel,
      Uint8List.fromList(img.encodeJpg(img.Image(width: 60, height: 40))),
    );
    await db.into(db.pages).insert(
          PagesCompanion.insert(
            documentId: id, position: 1, relativeImagePath: baseRel,
          ),
        );
    return id;
  }

  const crop = CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  );

  Future<img.Image> display(int id) async {
    final p = (await repo.getDocumentPages(id)).single;
    return img.decodeImage(File(p.flatImagePath!).readAsBytesSync())!;
  }

  Uint8List baseBytes() => store.absoluteFor(baseRel).readAsBytesSync();

  test('rotate once -> portrait 40x60', () async {
    final id = await seed();
    await repo.rotatePage(id, 1);
    final d = await display(id);
    expect([d.width, d.height], [40, 60]);
  });

  test('rotate twice -> 60x40; four times -> identity dims', () async {
    final id = await seed();
    await repo.rotatePage(id, 1);
    await repo.rotatePage(id, 1);
    expect([(await display(id)).width, (await display(id)).height], [60, 40]);
    await repo.rotatePage(id, 1);
    await repo.rotatePage(id, 1);
    expect([(await display(id)).width, (await display(id)).height], [60, 40]);
  });

  test('rotate THEN crop keeps the rotation (portrait stays portrait)',
      () async {
    final id = await seed();
    await repo.rotatePage(id, 1); // 60x40 -> 40x60
    await repo.updatePageCorners(id, 1, crop);
    final d = await display(id);
    expect(d.height, greaterThan(d.width),
        reason: 'rotation must survive a later crop');
  });

  test('crop THEN rotate swaps the cropped dims', () async {
    final id = await seed();
    await repo.updatePageCorners(id, 1, crop);
    final afterCrop = await display(id);
    await repo.rotatePage(id, 1);
    final afterRot = await display(id);
    expect(afterRot.width, afterCrop.height);
    expect(afterRot.height, afterCrop.width);
  });

  test('crop -> rotate -> crop -> rotate does not throw and stays cropped',
      () async {
    final id = await seed();
    await repo.updatePageCorners(id, 1, crop);
    await repo.rotatePage(id, 1);
    await repo.updatePageCorners(id, 1, crop);
    await repo.rotatePage(id, 1);
    final p = (await repo.getDocumentPages(id)).single;
    expect(p.flatImagePath, isNotNull);
  });

  test('reset crop to fullFrame while rotated keeps rotation', () async {
    final id = await seed();
    await repo.rotatePage(id, 1); // portrait 40x60
    await repo.updatePageCorners(id, 1, crop);
    await repo.updatePageCorners(id, 1, CropCorners.fullFrame); // clear crop
    final d = await display(id);
    expect([d.width, d.height], [40, 60],
        reason: 'clearing crop returns the rotated full frame, not the base');
  });

  test('base bytes are never modified by crop or rotate', () async {
    final id = await seed();
    final before = baseBytes();
    await repo.rotatePage(id, 1);
    await repo.updatePageCorners(id, 1, crop);
    await repo.rotatePage(id, 1);
    expect(baseBytes(), before);
  });

  test('rotatePage throws for a missing page', () async {
    await seed();
    expect(() => repo.rotatePage(999, 1),
        throwsA(isA<DocumentSaveException>()));
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/composable_edits_test.dart`
Expected: FAIL — `rotate THEN crop` (and `reset crop` / `crop->rotate` dims) fail because the current crop discards rotation.

- [ ] **Step 3: Add `_writeFlat` and rewrite the two operations**

In `lib/features/library/drift/drift_document_repository.dart`, add this private method (place it directly above `updatePageCorners`):

```dart
  /// Regenerates the display ("flat") derivative from the PRISTINE base by
  /// applying rotate-then-crop, and returns the new flat's relative path (or
  /// null when the display equals the base: no rotation and no crop). NEVER
  /// writes the base. [corners] are in the display frame (post-rotation).
  Future<String?> _writeFlat({
    required String relativeImagePath,
    required int quarterTurns,
    required CropCorners corners,
    required String? existingFlatRel,
  }) async {
    final baseBytes = await _fileStore.absoluteFor(relativeImagePath).readAsBytes();
    img.Image? decoded;
    try {
      decoded = img.decodeImage(baseBytes);
    } catch (_) {
      decoded = null;
    }
    if (decoded == null) {
      throw const DocumentSaveException('regenerate: undecodable base image');
    }
    final rotated = quarterTurns == 0
        ? decoded
        : img.copyRotate(decoded, angle: 90 * quarterTurns);
    final isFullFrame = corners == CropCorners.fullFrame;

    Uint8List? flatBytes;
    if (isFullFrame) {
      flatBytes = quarterTurns == 0
          ? null // display == base
          : Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
    } else {
      final rotatedBytes = Uint8List.fromList(img.encodeJpg(rotated, quality: 95));
      final warped = await _warper.warp(rotatedBytes, corners);
      // A null warp means "crop not applied" — fall back to the rotated-only
      // image (or the base when there is no rotation either).
      flatBytes = warped ?? (quarterTurns == 0 ? null : rotatedBytes);
    }

    if (flatBytes == null) {
      if (existingFlatRel != null) {
        try {
          await _fileStore.absoluteFor(existingFlatRel).delete();
        } on FileSystemException {
          /* already gone — fine */
        }
      }
      return null;
    }
    final flatRel = existingFlatRel ?? _fileStore.flatForImage(relativeImagePath);
    await _fileStore.writeRelative(flatRel, flatBytes);
    return flatRel;
  }
```

Replace the entire body of `updatePageCorners` with:

```dart
  @override
  Future<void> updatePageCorners(
    int documentId,
    int position,
    CropCorners corners,
  ) async {
    final page =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (page == null) {
      throw DocumentSaveException(
        'updatePageCorners: no page ($documentId, $position)',
      );
    }
    // Corners arrive already in the DISPLAY frame (post-rotation) from the
    // editor; rotation is unchanged by a crop.
    final flatRel = await _writeFlat(
      relativeImagePath: page.relativeImagePath,
      quarterTurns: page.rotationQuarterTurns,
      corners: corners,
      existingFlatRel: page.flatRelativePath,
    );
    final isFullFrame = corners == CropCorners.fullFrame;
    await (_db.update(_db.pages)..where(
          (t) => t.documentId.equals(documentId) & t.position.equals(position),
        ))
        .write(
          PagesCompanion(
            corners: Value(isFullFrame ? null : corners.toStorage()),
            flatRelativePath: Value(flatRel),
          ),
        );
  }
```

Replace the entire body of `rotatePage` with:

```dart
  @override
  Future<void> rotatePage(int documentId, int position) async {
    final row =
        await (_db.select(_db.pages)..where(
              (t) =>
                  t.documentId.equals(documentId) & t.position.equals(position),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw DocumentSaveException(
        'rotatePage: no page ($documentId, $position)',
      );
    }
    final turns = (row.rotationQuarterTurns + 1) % 4;
    // Keep the same physical crop in the newly-rotated display frame.
    final corners =
        (CropCorners.tryParse(row.corners) ?? CropCorners.fullFrame)
            .rotate90Cw();
    final isFullFrame = corners == CropCorners.fullFrame;
    final flatRel = await _writeFlat(
      relativeImagePath: row.relativeImagePath,
      quarterTurns: turns,
      corners: corners,
      existingFlatRel: row.flatRelativePath,
    );

    // Rotate cached OCR boxes CW to stay aligned; text is unchanged.
    final boxes = OcrResult.decodeBoxes(row.ocrBoxes);
    final String? newBoxes = boxes.isEmpty
        ? row.ocrBoxes
        : OcrResult(
            text: '',
            words: [for (final b in boxes) b.rotate90Cw()],
          ).encodeBoxes();

    await (_db.update(_db.pages)..where(
          (t) => t.documentId.equals(documentId) & t.position.equals(position),
        ))
        .write(
          PagesCompanion(
            rotationQuarterTurns: Value(turns),
            corners: Value(isFullFrame ? null : corners.toStorage()),
            flatRelativePath: Value(flatRel),
            ocrBoxes: Value(newBoxes),
          ),
        );
    await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
        .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
  }
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/composable_edits_test.dart`
Expected: PASS (all tests).

- [ ] **Step 5: Full suite (this touches shared repo code)**

Run: `flutter test`
Expected: green except the 2 known `opencv_edge_detector_test.dart` host-env failures. If any OTHER test fails (e.g. an old `rotate_page_test.dart` asserting the previous flat-based behavior), read it: update assertions that encoded the OLD non-composable behavior to the new metadata model; do NOT weaken a test that catches a real regression.

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format lib/features/library/drift/drift_document_repository.dart test/features/library/composable_edits_test.dart
flutter analyze lib/features/library/drift/drift_document_repository.dart
git add lib/features/library/drift/drift_document_repository.dart test/features/library/composable_edits_test.dart
# plus any existing test files you had to update in Step 5 (name them explicitly)
git commit -m "fix(library): compose crop+rotate via regeneration from pristine base"
```

---

### Task 5: Retake (`replacePage`) resets the transform chain

**Files:**
- Modify: `lib/features/library/drift/drift_document_repository.dart` (`replacePage` ~873–964)
- Test: `test/features/library/replace_page_resets_rotation_test.dart` (create)

**Interfaces:**
- Consumes: `_writeFlat` (Task 4), `rotationQuarterTurns` column.
- Produces: `replacePage` writes the new base, then sets `rotationQuarterTurns = 0`, `corners` = capture corners (or null for full frame), and regenerates the flat via `_writeFlat`. Signature unchanged.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/library/replace_page_resets_rotation_test.dart
import 'dart:io';
import 'dart:typed_data';
import 'package:drift/native.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/hybrid_warper.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

void main() {
  test('replacePage resets rotationQuarterTurns to 0', () async {
    final base = await Directory.systemTemp.createTemp('retake');
    final db = AppDatabase(NativeDatabase.memory());
    final store = DocumentFileStore(base);
    final repo = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: store,
      clock: DateTime.now,
      pdfBuilder: const PdfBuilder(),
      warper: const HybridWarper(),
    );
    addTearDown(() async {
      await db.close();
      if (await base.exists()) await base.delete(recursive: true);
    });
    final now = DateTime.now();
    final id = await db.into(db.documents).insert(
          DocumentsCompanion.insert(name: 'D', createdAt: now, modifiedAt: now),
        );
    final rel = 'documents/$id/page_1.jpg';
    await store.writeRelative(
      rel,
      Uint8List.fromList(img.encodeJpg(img.Image(width: 40, height: 20))),
    );
    await db.into(db.pages).insert(
          PagesCompanion.insert(
            documentId: id,
            position: 1,
            relativeImagePath: rel,
            rotationQuarterTurns: const Value(3),
          ),
        );
    // A fresh capture image on disk.
    final capPath = '${base.path}/cap.jpg';
    File(capPath).writeAsBytesSync(
      img.encodeJpg(img.Image(width: 40, height: 20)),
    );

    await repo.replacePage(id, 1, CapturedImage(capPath));

    final page = await (db.select(db.pages)
          ..where((t) => t.documentId.equals(id)))
        .getSingle();
    expect(page.rotationQuarterTurns, 0);
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/replace_page_resets_rotation_test.dart`
Expected: FAIL — `rotationQuarterTurns` stays 3 (replacePage never resets it).

- [ ] **Step 3: Rewrite `replacePage`'s flat handling**

First, make the base the **enhanced canvas** so future re-crops of the retaken page stay enhanced (the flat is now regenerated by warping the base). Change the enhancement guard from full-frame-only to "whenever an enhancer is present":

```dart
      // Base is the enhanced full-frame canvas; edits re-derive from it.
      Uint8List bytesToStore = scrubbed;
      if (enhancer != null) {
        final enhanced = await _processor.process(
          scrubbed,
          CropCorners.fullFrame,
          enhancerModeOf(enhancer),
        );
        if (enhanced != null) {
          bytesToStore = enhanced;
        } else {
          try {
            bytesToStore = await enhancer.enhance(scrubbed);
          } catch (_) {}
        }
      }
      // Overwrite the base in place (same stored relative path).
      await _fileStore.writeRelative(row.relativeImagePath, bytesToStore);
```
(This replaces the existing `bytesToStore`/`isFullFrame` enhancement block and its base write. `isFullFrame` is no longer needed there.)

Then replace the flat block (the `String? flatRel; if (!isFullFrame) { ... }` through the `if (flatRel == null && row.flatRelativePath != null) { ...delete... }` block) with:

```dart
      // Retake = a fresh image: reset the transform chain to identity, then
      // regenerate the flat from the (new) base via the shared pipeline.
      final CropCorners effective = corners ?? CropCorners.fullFrame;
      final flatRel = await _writeFlat(
        relativeImagePath: row.relativeImagePath,
        quarterTurns: 0,
        corners: effective,
        existingFlatRel: row.flatRelativePath,
      );
```

Update the row-write inside the transaction to reset rotation and store corners consistently:

```dart
      await _db.transaction(() async {
        await (_db.update(_db.pages)..where((t) => t.id.equals(row.id))).write(
          PagesCompanion(
            rotationQuarterTurns: const Value(0),
            corners: Value(
              (corners == null || corners == CropCorners.fullFrame)
                  ? null
                  : corners.toStorage(),
            ),
            flatRelativePath: Value(flatRel),
          ),
        );
        await (_db.update(_db.documents)..where((d) => d.id.equals(documentId)))
            .write(DocumentsCompanion(modifiedAt: Value(_clock().toUtc())));
      });
```

(The `enhancer`-on-flat behaviour is now covered by `_writeFlat` warping the enhanced base; drop the old per-flat `enhancer.enhance(flat)` call and the manual stale-flat delete — `_writeFlat` deletes the old flat when it returns null.)

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/replace_page_resets_rotation_test.dart`
Expected: PASS.

- [ ] **Step 5: Full suite (shared repo code + existing replace_page_test.dart)**

Run: `flutter test test/features/library/replace_page_test.dart test/features/library/replace_page_resets_rotation_test.dart`
Then: `flutter test`
Expected: green except the 2 known opencv-env failures. If `replace_page_test.dart` asserted the old flat/enhancer wiring, update those assertions to the regeneration model (name the file in the commit).

- [ ] **Step 6: Format, analyze, commit**

```bash
dart format lib/features/library/drift/drift_document_repository.dart test/features/library/replace_page_resets_rotation_test.dart
flutter analyze lib/features/library/drift/drift_document_repository.dart
git add lib/features/library/drift/drift_document_repository.dart test/features/library/replace_page_resets_rotation_test.dart
# plus replace_page_test.dart if you updated it
git commit -m "fix(library): retake resets rotation and regenerates via pipeline"
```

---

### Task 6: `EditCropScreen` shows the rotated (display) view

**Files:**
- Modify: `lib/features/library/edit_crop_screen.dart`
- Test: `test/features/library/edit_crop_rotated_view_test.dart` (create)

**Interfaces:**
- Consumes: `PageImage.rotationQuarterTurns` (Task 3), existing `CropOverlay`, `_resolveImageSize`.
- Produces: `EditCropScreen` gains `final int quarterTurns` (default 0). It wraps the image in `RotatedBox(quarterTurns: quarterTurns)` and, when resolving image size, swaps width/height for odd `quarterTurns` so the overlay maps to the displayed (rotated) image. Accept still pops the (display-frame) `CropCorners`.

- [ ] **Step 1: Write the failing test**

```dart
// test/features/library/edit_crop_rotated_view_test.dart
import 'dart:ui' show Size;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/edit_crop_screen.dart';

void main() {
  testWidgets('odd quarterTurns wraps the image in a RotatedBox', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: EditCropScreen(
          imagePath: '/nonexistent.jpg',
          initialCorners: CropCorners.fullFrame,
          quarterTurns: 1,
          decodeImageSize: (_) async => const Size(60, 40),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final rotated = tester.widgetList<RotatedBox>(find.byType(RotatedBox));
    expect(
      rotated.any((r) => r.quarterTurns % 4 == 1),
      isTrue,
      reason: 'the crop image must be rotated to the display orientation',
    );
  });
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/edit_crop_rotated_view_test.dart`
Expected: FAIL — `EditCropScreen` has no `quarterTurns` parameter.

- [ ] **Step 3: Implement the rotated view**

In `lib/features/library/edit_crop_screen.dart`:

Add the field + constructor param:
```dart
  final int quarterTurns;
```
Constructor (add after `required this.initialCorners,`):
```dart
    this.quarterTurns = 0,
```

Change `initState`'s size resolution to swap for odd turns:
```dart
    widget
        .decodeImageSize(widget.imagePath)
        .then((size) {
          if (!mounted) return;
          final oddTurn = widget.quarterTurns.isOdd;
          setState(() => _imageSize = oddTurn
              ? Size(size.height, size.width)
              : size);
        })
        .catchError((_) {
          /* leave _imageSize null — overlay skipped, image still shown */
        });
```

Wrap the image widget in a `RotatedBox`:
```dart
  Widget _imageWidget(ReamColors r) => RotatedBox(
    quarterTurns: widget.quarterTurns,
    child: Image.file(
      File(widget.imagePath),
      key: const Key('edit-crop-image'),
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Center(
        child: Icon(Icons.broken_image_outlined, color: r.muted, size: 64),
      ),
    ),
  );
```

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/edit_crop_rotated_view_test.dart`
Then: `flutter test test/features/library/edit_crop_screen_test.dart`
Expected: both PASS (existing edit_crop_screen_test still green — default `quarterTurns` 0 keeps old behavior).

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/library/edit_crop_screen.dart test/features/library/edit_crop_rotated_view_test.dart
flutter analyze lib/features/library/edit_crop_screen.dart
git add lib/features/library/edit_crop_screen.dart test/features/library/edit_crop_rotated_view_test.dart
git commit -m "feat(library): crop editor shows the rotated display view"
```

---

### Task 7: Page viewer — pass `quarterTurns`, clear cache on every edit

**Files:**
- Modify: `lib/features/library/page_viewer_screen.dart` (`_editCrop` ~418–440, `_rotatePage` ~398–416, `_retakePage` ~343+)
- Test: `test/features/library/page_viewer_edit_reload_test.dart` (create)

**Interfaces:**
- Consumes: `EditCropScreen.quarterTurns` (Task 6), `PageImage.rotationQuarterTurns` (Task 3).
- Produces: `_editCrop` passes `quarterTurns: pg.rotationQuarterTurns` to `EditCropScreen`; a shared `_reloadAfterEdit()` clears the Flutter image cache and reloads, called by crop, rotate, and retake (so a regenerated flat at a reused path never shows stale).

- [ ] **Step 1: Write the failing test**

```dart
// test/features/library/page_viewer_edit_reload_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/edit_crop_screen.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';

import '../../support/fake_library.dart';

void main() {
  testWidgets('crop passes the page rotation into the editor', (tester) async {
    final repo = FakeDocumentRepository(
      pages: const [
        PageImage(position: 1, imagePath: '/a.jpg', rotationQuarterTurns: 1),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('page-viewer-edit')));
    await tester.pumpAndSettle();

    final editor = tester.widget<EditCropScreen>(find.byType(EditCropScreen));
    expect(editor.quarterTurns, 1);
  });
}
```

Note: the Crop button's key is `page-viewer-edit` (see `lib/features/library/widgets/editor_toolbar.dart:41`).

- [ ] **Step 2: Run to verify it fails**

Run: `flutter test test/features/library/page_viewer_edit_reload_test.dart`
Expected: FAIL — `EditCropScreen.quarterTurns` is 0 (not passed).

- [ ] **Step 3: Wire it**

In `lib/features/library/page_viewer_screen.dart`, add a shared reload helper (place near `_load`):
```dart
  Future<void> _reloadAfterEdit() async {
    // The regenerated flat reuses its file path; FileImage caches by path, so
    // clear the cache before reloading or the stale image would show.
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (!mounted) return;
    await _load();
  }
```

In `_editCrop`, pass the rotation and use the shared reload:
```dart
        builder: (_) => EditCropScreen(
          imagePath: pg.imagePath,
          initialCorners: pg.corners,
          quarterTurns: pg.rotationQuarterTurns,
        ),
```
and replace its `await _load();` (in the try block) with `await _reloadAfterEdit();`.

In `_rotatePage`, replace the three cache-clear lines + `await _load();` with `await _reloadAfterEdit();`.

In `_retakePage`'s success path, ensure it calls `await _reloadAfterEdit();` after `replacePage` returns (replace its existing reload/`_load` call).

- [ ] **Step 4: Run to verify it passes**

Run: `flutter test test/features/library/page_viewer_edit_reload_test.dart`
Then: `flutter test test/features/library/page_viewer_rotate_test.dart test/features/library/page_viewer_screen_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, commit**

```bash
dart format lib/features/library/page_viewer_screen.dart test/features/library/page_viewer_edit_reload_test.dart
flutter analyze lib/features/library/page_viewer_screen.dart
git add lib/features/library/page_viewer_screen.dart test/features/library/page_viewer_edit_reload_test.dart
git commit -m "feat(library): pass rotation to crop editor; clear cache on every edit"
```

---

### Task 8: BDD mixed re-edit journey (host + device feature)

**Files:**
- Create: `integration_test/e4_mixed_reedit.feature`
- Generate: `integration_test/e4_mixed_reedit_test.dart` (via build_runner — do NOT hand-write)
- Create step(s) as needed in `test/step/` (reuse existing steps where present)
- Test: the generated `e4_mixed_reedit_test.dart`

**Interfaces:**
- Consumes: existing steps — `a document with a real page image was saved to persistent storage earlier`, `the app launches reading that same storage`, `I open the first document`, `I see the page viewer`, `I tap the edit crop button`, `I see the crop overlay`, `I drag the top left crop corner`, `I tap Accept on the viewer`, `I rotate the page` (`test/step/i_rotate_the_page.dart`).
- Produces: a scenario that rotates and crops repeatedly and asserts the viewer survives (no error widget).

- [ ] **Step 1: Write the feature (failing — no generated test yet)**

```gherkin
# integration_test/e4_mixed_reedit.feature
Feature: Mixed re-edit of a page
  Scenario: Rotate and crop repeatedly without error
    Given a document with a real page image was saved to persistent storage earlier
    When the app launches reading that same storage
    And I open the first document
    Then I see the page viewer
    When I rotate the page
    And I tap the edit crop button
    Then I see the crop overlay
    When I drag the top left crop corner
    And I tap Accept on the viewer
    Then I see the page viewer
    When I rotate the page
    And I tap the edit crop button
    Then I see the crop overlay
    When I drag the top left crop corner
    And I tap Accept on the viewer
    Then I see the page viewer
```

- [ ] **Step 2: Generate the test + verify a step gap fails loudly if any**

Run: `dart run build_runner build --delete-conflicting-outputs`
Expected: generates `integration_test/e4_mixed_reedit_test.dart`. If build reports an undefined step, create it in `test/step/` mirroring the existing sibling step's implementation, then re-run build_runner.

- [ ] **Step 3: Run on host**

Run: `flutter test integration_test/e4_mixed_reedit_test.dart`
Expected: PASS. (Host runs this widget-level; native warp falls back to the Dart warper.) If it fails because a step needs adjusting, fix the step (not the feature intent).

- [ ] **Step 4: Format, analyze, commit (scoped — watch build_runner output)**

```bash
dart format integration_test/e4_mixed_reedit_test.dart test/step/
flutter analyze integration_test/ test/step/
git status   # confirm ONLY e4 feature/test + any new step files are modified
git add integration_test/e4_mixed_reedit.feature integration_test/e4_mixed_reedit_test.dart
# add ONLY new/changed step files you created, by name
git commit -m "test(library): BDD mixed rotate+crop re-edit journey"
```
If build_runner regenerated other features' `*_test.dart`, do NOT stage them.

---

### Task 9 (controller-run gate): device verification on Android + iOS

This task is NOT a subagent implementation task — it is the non-negotiable device gate, run by the controller after Tasks 1–8 are merged-ready.

- [ ] Android real device: `flutter test integration_test/e4_mixed_reedit_test.dart -d <android-device-id>` → PASS. Also run `integration_test/k1_rotate_page_device_test.dart` and `integration_test/e1_crop*` / `e3_reedit_test.dart` on device to confirm no regression.
- [ ] iOS real device/sim: same commands with `-d <ios-device-id>` → PASS.
- [ ] Manual smoke on one device: scan a page, then rotate → crop → rotate → crop; confirm the image composes correctly and re-cropping from the rotated view works, and that a retake resets orientation.
- [ ] Record exact device IDs and green output. If a device-only failure appears (e.g. EXIF orientation mismatch between `RotatedBox` and `img.copyRotate`, or opencv warp on a rotated buffer), STOP and treat it as a new systematic-debugging cycle — do not paper over it.

---

## Notes for the implementer

- **Migration limitation (documented, expected):** a legacy page rotated before v7 has `rotationQuarterTurns == 0` after upgrade; its previously-baked rotation is lost on its next edit (regenerated from base). Do not add heuristics to "recover" it — out of scope.
- **EXIF:** the stored base is treated as EXIF-neutral (the scrub/enhance path already encodes orientation-baked JPEGs; existing crop/rotate rely on this). `_writeFlat` rotates via `img.copyRotate` (pure pixels), matching how the editor's `RotatedBox` rotates the framework-decoded image. Any mismatch is a device-gate finding (Task 9).
- **Scan-time creation is intentionally untouched:** `createFromCapture`/`addPageToDocument` insert without `rotationQuarterTurns` (DB default 0) and keep their existing flat logic. Only the EDIT operations change.
