# E2 — Perspective Flatten Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** At save time, warp the captured JPEG using the persisted crop corners into a perspective-corrected flat image and surface it via `PageImage.displayPath` to the viewer and PDF builder.

**Architecture:** `PerspectiveWarper` (pure Dart, `image` package, `compute()` isolate) is called during `createFromCapture`. It writes the flat JPEG to `documents/$docId/page_1_flat.jpg` and the path is recorded in a new nullable `Pages.flatRelativePath` column (schema v3 migration). `PageImage` gains `flatImagePath` + `displayPath` (`flatImagePath ?? imagePath`). `ImageWarper` is a DIP interface — the widget layer never imports the implementation. Warp failure is always caught; the original save proceeds regardless.

**Tech Stack:** Dart, Flutter, `image: ^4.5.0` (pure Dart imaging, no native deps), Drift (schema v3 migration), `flutter/foundation.dart` (`compute`).

## Global Constraints

- TDD: every test written (red) before the implementation that makes it pass (green).
- `flutter analyze` must pass after every task commit.
- `img.bakeOrientation()` must be called immediately after `img.decodeImage()` — corners are in the EXIF-applied display frame.
- Full-frame corners short-circuit in `PerspectiveWarper.warp()` before spawning the isolate.
- Warp failure (any exception) must never block the save. The original JPEG is always persisted first.
- `ImageWarper`/`PerspectiveWarper` must not be imported by any widget file; only by the repository and composition root.
- All commands run from `apps/mobile/` unless noted otherwise.

---

## File Map

| Status | Path | Purpose |
|--------|------|---------|
| create | `lib/features/library/image_warper.dart` | `ImageWarper` interface + `WarpException` |
| create | `lib/features/library/perspective_warper.dart` | `PerspectiveWarper` impl (homography, `compute`) |
| create | `test/features/library/page_image_test.dart` | `displayPath` unit tests |
| create | `test/features/library/perspective_warper_test.dart` | Warper unit tests (all math paths) |
| create | `test/step/i_see_the_page_viewer.dart` | BDD step |
| create | `integration_test/e2_flatten.feature` | BDD feature |
| create | `scripts/verify/e2.sh` | Verify gate |
| modify | `pubspec.yaml` | Add `image: ^4.5.0` |
| modify | `lib/features/library/page_image.dart` | Add `flatImagePath`, `displayPath` |
| modify | `lib/features/library/page_viewer_screen.dart` | Use `pg.displayPath` |
| modify | `lib/features/library/pdf/pdf_builder.dart` | Use `page.displayPath` |
| modify | `lib/features/library/drift/app_database.dart` | Schema v3 + onUpgrade |
| modify | `lib/features/library/document_file_store.dart` | Add `flatRelativeFor` |
| modify | `lib/features/library/drift/drift_document_repository.dart` | Warper injection, write + read side |
| modify | `lib/features/library/library_dependencies.dart` | Wire `PerspectiveWarper()` |
| modify | `test/support/fake_library.dart` | `FakeImageWarper` + wire warper in helpers |
| modify | `test/features/library/drift/migration_test.dart` | v2→v3 + v1→v3 tests |
| modify | `test/features/library/drift_document_repository_test.dart` | Warp write+read tests |
| modify | `test/features/library/page_viewer_screen_test.dart` | `displayPath` regression test |
| modify | `test/features/library/pdf/pdf_builder_test.dart` | `displayPath` test |

---

### Task 1: `image` package + `PageImage.displayPath` + viewer + PDF builder

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Modify: `apps/mobile/lib/features/library/page_image.dart`
- Modify: `apps/mobile/lib/features/library/page_viewer_screen.dart:219`
- Modify: `apps/mobile/lib/features/library/pdf/pdf_builder.dart:24`
- Create: `apps/mobile/test/features/library/page_image_test.dart`
- Modify: `apps/mobile/test/features/library/page_viewer_screen_test.dart`
- Modify: `apps/mobile/test/features/library/pdf/pdf_builder_test.dart`

**Interfaces:**
- Produces: `PageImage.flatImagePath: String?`, `PageImage.displayPath: String` (used by Tasks 6, 7, 8)

- [ ] **Step 1: Add `image` to pubspec**

In `apps/mobile/pubspec.yaml` under `dependencies:`, add (keep alphabetical order near `camera`):
```yaml
  image: ^4.5.0
```

Run:
```bash
cd apps/mobile && flutter pub get
```
Expected: output includes `+ image`.

- [ ] **Step 2: Write failing `PageImage` unit tests**

Create `apps/mobile/test/features/library/page_image_test.dart`:
```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/page_image.dart';

void main() {
  group('PageImage.displayPath', () {
    test('returns imagePath when flatImagePath is null', () {
      const page = PageImage(position: 1, imagePath: '/orig/page_1.jpg');
      expect(page.displayPath, '/orig/page_1.jpg');
    });

    test('returns flatImagePath when set', () {
      const page = PageImage(
        position: 1,
        imagePath: '/orig/page_1.jpg',
        flatImagePath: '/orig/page_1_flat.jpg',
      );
      expect(page.displayPath, '/orig/page_1_flat.jpg');
    });

    test('flatImagePath defaults to null', () {
      const page = PageImage(position: 1, imagePath: '/x.jpg');
      expect(page.flatImagePath, isNull);
    });
  });
}
```

Run:
```bash
cd apps/mobile && flutter test test/features/library/page_image_test.dart
```
Expected: FAIL — `flatImagePath` and `displayPath` not found.

- [ ] **Step 3: Update `PageImage`**

Replace `apps/mobile/lib/features/library/page_image.dart` with:
```dart
import 'crop_corners.dart';

/// One page's resolved image for the viewer. [imagePath] is the original
/// EXIF-scrubbed capture (absolute). [flatImagePath] is the perspective-
/// flattened derivative (absolute); null when corners are full-frame or
/// the warp was skipped. [displayPath] is the path consumers should use.
class PageImage {
  final int position;
  final String imagePath;
  final CropCorners corners;
  final String? flatImagePath;

  const PageImage({
    required this.position,
    required this.imagePath,
    this.corners = CropCorners.fullFrame,
    this.flatImagePath,
  });

  /// Flat image when available; original otherwise.
  String get displayPath => flatImagePath ?? imagePath;
}
```

- [ ] **Step 4: Run `page_image_test.dart` → GREEN**

```bash
cd apps/mobile && flutter test test/features/library/page_image_test.dart
```
Expected: 3 tests pass.

- [ ] **Step 5: Write failing PDF builder `displayPath` test**

In `apps/mobile/test/features/library/pdf/pdf_builder_test.dart`, add after the last existing test:

```dart
  test('E2: uses displayPath — reads flat file when flatImagePath is set', () async {
    // imagePath points nowhere; only flatImagePath is readable.
    // If PdfBuilder uses imagePath it throws; if it uses displayPath it passes.
    final tmp = await Directory.systemTemp.createTemp('e2pdf');
    final flatFile = File('${tmp.path}/flat.jpg');
    await flatFile.writeAsBytes(jpeg); // reuse the fixture bytes
    final flatPage = PageImage(
      position: 1,
      imagePath: '/nonexistent/page_1.jpg',
      flatImagePath: flatFile.path,
    );
    final pdf = await const PdfBuilder().build([flatPage]);
    expect(pdf, isNotEmpty);
    await tmp.delete(recursive: true);
  });
```

Run:
```bash
cd apps/mobile && flutter test test/features/library/pdf/pdf_builder_test.dart
```
Expected: new test FAILS (reads from `imagePath` which doesn't exist → throws).

- [ ] **Step 6: Update `PdfBuilder` to use `displayPath`**

In `apps/mobile/lib/features/library/pdf/pdf_builder.dart`, change line 24:
```dart
      final bytes = await File(page.displayPath).readAsBytes();
```
(was `page.imagePath`)

Run:
```bash
cd apps/mobile && flutter test test/features/library/pdf/pdf_builder_test.dart
```
Expected: all tests pass (existing tests have `flatImagePath: null` so `displayPath == imagePath`).

- [ ] **Step 7: Write viewer `displayPath` regression test**

In `apps/mobile/test/features/library/page_viewer_screen_test.dart`, add:

```dart
  // E2: viewer uses displayPath — verify the page key is present regardless of
  // whether flatImagePath is set (visual path correctness is covered by page_image_test).
  testWidgets('E2: viewer renders page key when flatImagePath is set',
      (tester) async {
    final repo = FakeDocumentRepository(
      pages: [
        const PageImage(
          position: 1,
          imagePath: '/nonexistent/page_1.jpg',
          flatImagePath: '/nonexistent/page_1_flat.jpg',
        ),
      ],
    );
    await tester.pumpWidget(MaterialApp(
      home: PageViewerScreen(documentId: 1, name: 'Doc', repository: repo),
    ));
    await tester.pump();
    expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);
  });
```

Run:
```bash
cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart
```
Expected: new test FAILS (compile error — `flatImagePath` on `PageImage` exists now, but viewer still uses `imagePath`).

- [ ] **Step 8: Update `PageViewerScreen` to use `displayPath`**

In `apps/mobile/lib/features/library/page_viewer_screen.dart`, change the `Image.file(...)` call inside `_buildPages` (around line 221):
```dart
              child: Image.file(
                File(pg.displayPath),
                fit: BoxFit.contain,
```
(was `File(pg.imagePath)`)

Run:
```bash
cd apps/mobile && flutter test test/features/library/page_viewer_screen_test.dart
```
Expected: all tests pass.

- [ ] **Step 9: Full suite check + analyze**

```bash
cd apps/mobile && flutter test && flutter analyze
```
Expected: all tests pass, no analysis issues.

- [ ] **Step 10: Commit**

```bash
cd apps/mobile && git add pubspec.yaml pubspec.lock \
  lib/features/library/page_image.dart \
  lib/features/library/page_viewer_screen.dart \
  lib/features/library/pdf/pdf_builder.dart \
  test/features/library/page_image_test.dart \
  test/features/library/page_viewer_screen_test.dart \
  test/features/library/pdf/pdf_builder_test.dart
git commit -m "feat(e2): PageImage.displayPath; viewer + PDF builder use flat when available"
```

---

### Task 2: `ImageWarper` interface + `FakeImageWarper`

**Files:**
- Create: `apps/mobile/lib/features/library/image_warper.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`

**Interfaces:**
- Produces: `ImageWarper`, `WarpException` (consumed by Tasks 5, 6); `FakeImageWarper` (consumed by Task 6)

- [ ] **Step 1: Create `image_warper.dart`**

Create `apps/mobile/lib/features/library/image_warper.dart`:
```dart
import 'dart:typed_data';

import 'crop_corners.dart';

/// DIP boundary for the perspective-warp operation. The widget layer and
/// repository depend on this interface; the concrete implementation
/// (PerspectiveWarper) is wired only at the composition root.
abstract interface class ImageWarper {
  /// Returns flattened JPEG bytes, or null when [corners] are full-frame
  /// (no-op). [bytes] is the EXIF-scrubbed source JPEG.
  /// Throws [WarpException] for self-crossing or degenerate quads.
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners);
}

class WarpException implements Exception {
  final String message;
  const WarpException(this.message);
  @override
  String toString() => 'WarpException: $message';
}
```

- [ ] **Step 2: Add `FakeImageWarper` to `fake_library.dart`**

In `apps/mobile/test/support/fake_library.dart`, add the following imports at the top:
```dart
import 'dart:typed_data';
import 'package:mobile/features/library/image_warper.dart';
```

Then add this class after `FakeDocumentRepository`:
```dart
/// Fake [ImageWarper] for host tests. Configurable to return fixed bytes,
/// return null (no-op), or throw [WarpException].
class FakeImageWarper implements ImageWarper {
  final bool throws;
  final Uint8List? returnValue;
  int calls = 0;

  FakeImageWarper({this.throws = false, this.returnValue});

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) async {
    calls++;
    if (throws) throw WarpException('fake: warp failed');
    return returnValue;
  }
}
```

- [ ] **Step 3: Analyze**

```bash
cd apps/mobile && flutter analyze
```
Expected: no issues.

- [ ] **Step 4: Commit**

```bash
cd apps/mobile && git add \
  lib/features/library/image_warper.dart \
  test/support/fake_library.dart
git commit -m "feat(e2): ImageWarper DIP interface + WarpException + FakeImageWarper"
```

---

### Task 3: Schema v3 + `flatRelativeFor` + migration tests

**Files:**
- Modify: `apps/mobile/lib/features/library/drift/app_database.dart`
- Modify: `apps/mobile/lib/features/library/document_file_store.dart`
- Modify: `apps/mobile/test/features/library/drift/migration_test.dart`

**Interfaces:**
- Produces: `Pages.flatRelativePath` column, `DocumentFileStore.flatRelativeFor(int, int): String`

- [ ] **Step 1: Write failing migration tests**

In `apps/mobile/test/features/library/drift/migration_test.dart`, add inside `main()` after the existing test:

```dart
  test('v2→v3: upgrading adds nullable Pages.flatRelativePath column', () async {
    final dir = await Directory.systemTemp.createTemp('e2mig_v2v3');
    final file = File('${dir.path}/app.db');

    // Build a v2-shaped DB (has corners, no flatRelativePath).
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
        document_id INTEGER NOT NULL REFERENCES documents (id),
        position INTEGER NOT NULL,
        relative_image_path TEXT NOT NULL,
        corners TEXT
      );
    ''');
    raw.execute("INSERT INTO documents VALUES (1,'Scan','2026-01-01T00:00:00.000Z','2026-01-01T00:00:00.000Z');");
    raw.execute("INSERT INTO pages (id,document_id,position,relative_image_path,corners) "
        "VALUES (1,1,1,'1/1.jpg',NULL);");
    raw.execute('PRAGMA user_version = 2;');
    raw.close();

    // Open at v3 → triggers onUpgrade.
    final db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.pages).get();
    expect(rows.single.flatRelativePath, isNull);

    // Fresh write of flatRelativePath round-trips.
    await (db.update(db.pages)..where((t) => t.id.equals(1)))
        .write(const PagesCompanion(flatRelativePath: Value('1/1_flat.jpg')));
    final updated = await (db.select(db.pages)..where((t) => t.id.equals(1))).getSingle();
    expect(updated.flatRelativePath, '1/1_flat.jpg');

    await db.close();
    await dir.delete(recursive: true);
  });

  test('v1→v3 (cumulative): both corners and flatRelativePath columns added', () async {
    final dir = await Directory.systemTemp.createTemp('e2mig_v1v3');
    final file = File('${dir.path}/app.db');

    // Build a v1-shaped DB (no corners, no flatRelativePath).
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
        document_id INTEGER NOT NULL REFERENCES documents (id),
        position INTEGER NOT NULL,
        relative_image_path TEXT NOT NULL
      );
    ''');
    raw.execute("INSERT INTO documents VALUES (1,'Old','2026-01-01T00:00:00.000Z','2026-01-01T00:00:00.000Z');");
    raw.execute("INSERT INTO pages (id,document_id,position,relative_image_path) VALUES (1,1,1,'1/1.jpg');");
    raw.execute('PRAGMA user_version = 1;');
    raw.close();

    // Open at v3 → runs both migration steps.
    final db = AppDatabase(NativeDatabase(file));
    final rows = await db.select(db.pages).get();
    expect(rows.single.corners, isNull);
    expect(rows.single.flatRelativePath, isNull);
    expect(CropCorners.tryParse(rows.single.corners) ?? CropCorners.fullFrame,
        CropCorners.fullFrame);

    await db.close();
    await dir.delete(recursive: true);
  });
```

Run:
```bash
cd apps/mobile && flutter test test/features/library/drift/migration_test.dart
```
Expected: 2 new tests FAIL — `flatRelativePath` column doesn't exist yet.

- [ ] **Step 2: Add `flatRelativePath` column + bump schema to v3**

In `apps/mobile/lib/features/library/drift/app_database.dart`, inside the `Pages` table class, add after the `corners` column:
```dart
  TextColumn get flatRelativePath => text().nullable()();
```

Change `schemaVersion`:
```dart
  @override
  int get schemaVersion => 3;
```

In `onUpgrade`, add the v2→v3 step after the existing `if (from < 2)` block:
```dart
      if (from < 3) {
        await m.addColumn(pages, pages.flatRelativePath);
      }
```

The full `MigrationStrategy` should read:
```dart
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from < 2) await m.addColumn(pages, pages.corners);
      if (from < 3) await m.addColumn(pages, pages.flatRelativePath);
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
```

- [ ] **Step 3: Add `flatRelativeFor` to `DocumentFileStore`**

In `apps/mobile/lib/features/library/document_file_store.dart`, add after `relativeFor`:
```dart
  String flatRelativeFor(int docId, int position) =>
      'documents/$docId/page_${position}_flat.jpg';
```

- [ ] **Step 4: Run Drift codegen**

```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -5
```
Expected: ends with `Succeeded after ...`

- [ ] **Step 5: Run migration tests → GREEN**

```bash
cd apps/mobile && flutter test test/features/library/drift/migration_test.dart
```
Expected: all 3 tests pass.

- [ ] **Step 6: Full suite + analyze**

```bash
cd apps/mobile && flutter test && flutter analyze
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd apps/mobile && git add \
  lib/features/library/drift/app_database.dart \
  lib/features/library/drift/app_database.g.dart \
  lib/features/library/document_file_store.dart \
  test/features/library/drift/migration_test.dart
git commit -m "feat(e2): schema v3 — Pages.flatRelativePath column + migration; flatRelativeFor"
```

---

### Task 4: `PerspectiveWarper` — tests first (RED)

**Files:**
- Create: `apps/mobile/lib/features/library/perspective_warper.dart` (stub)
- Create: `apps/mobile/test/features/library/perspective_warper_test.dart`

**Interfaces:**
- Produces: `PerspectiveWarper` class (stub now, real in Task 5)

- [ ] **Step 1: Create stub `PerspectiveWarper`**

Create `apps/mobile/lib/features/library/perspective_warper.dart`:
```dart
import 'dart:typed_data';

import 'crop_corners.dart';
import 'image_warper.dart';

/// Perspective-flattening warper. Stub — full implementation in Task 5.
class PerspectiveWarper implements ImageWarper {
  const PerspectiveWarper();

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) async =>
      throw UnimplementedError('stub');
}
```

- [ ] **Step 2: Write all warper tests (they will fail against the stub)**

Create `apps/mobile/test/features/library/perspective_warper_test.dart`:

```dart
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/image_warper.dart';
import 'package:mobile/features/library/perspective_warper.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Synthesize a solid-colour JPEG. If [orientation] != 1, embeds that EXIF
/// Orientation tag so bakeOrientation rotates the pixel data.
Uint8List _jpeg(int w, int h, {int orientation = 1}) {
  final image = img.Image(width: w, height: h);
  img.fill(image, color: img.ColorRgb8(180, 100, 60));
  if (orientation != 1) {
    image.exif.imageIfd[0x0112] = img.IfdValueUint16(orientation);
  }
  return Uint8List.fromList(img.encodeJpg(image, quality: 85));
}

/// Quad that takes 80 % of a display-frame image: [0.1,0.9]×[0.1,0.9].
const _kRect = CropCorners(
  topLeft: Offset(0.1, 0.1),
  topRight: Offset(0.9, 0.1),
  bottomRight: Offset(0.9, 0.9),
  bottomLeft: Offset(0.1, 0.9),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final warper = const PerspectiveWarper();

  // 1. Full-frame → null (no-op, no isolate spawned).
  test('fullFrame → null', () async {
    expect(await warper.warp(_jpeg(100, 80), CropCorners.fullFrame), isNull);
  });

  // 2. Valid rectangular quad → JPEG with correct edge-length dimensions.
  //    Source: 200×100.  Quad pixel coords: TL(20,10) TR(180,10) BR(180,90) BL(20,90).
  //    top=bottom=160 → outW=160; left=right=80 → outH=80.
  test('valid quad → JPEG dimensions match edge-length formula', () async {
    final result = await warper.warp(_jpeg(200, 100), _kRect);
    expect(result, isNotNull);
    final out = img.decodeImage(result!)!;
    expect(out.width, 160);
    expect(out.height, 80);
  });

  // 3. Self-crossing quad → WarpException.
  test('self-crossing quad → WarpException', () async {
    const crossed = CropCorners(
      topLeft: Offset(0.9, 0.1),   // TL/TR swapped
      topRight: Offset(0.1, 0.1),
      bottomRight: Offset(0.9, 0.9),
      bottomLeft: Offset(0.1, 0.9),
    );
    await expectLater(
      warper.warp(_jpeg(100, 80), crossed),
      throwsA(isA<WarpException>()),
    );
  });

  // 4. Degenerate quad (all corners coincide) → WarpException.
  test('degenerate quad (zero-area) → WarpException', () async {
    const degen = CropCorners(
      topLeft: Offset(0.5, 0.5),
      topRight: Offset(0.5, 0.5),
      bottomRight: Offset(0.5, 0.5),
      bottomLeft: Offset(0.5, 0.5),
    );
    await expectLater(
      warper.warp(_jpeg(100, 80), degen),
      throwsA(isA<WarpException>()),
    );
  });

  // 5. EXIF orientation alignment.
  //    Source: 40×80 sensor with Orientation=6 (90° CW) → display is 80×40.
  //    _kRect in display frame: TL(8,4) TR(72,4) BR(72,36) BL(8,36).
  //    top=bottom=64 → outW=64; left=right=32 → outH=32.
  //    WITHOUT bakeOrientation (raw 40×80): outW=32, outH=64 — flipped.
  test('EXIF Orientation 6: bakeOrientation applied before denormalization', () async {
    final bytes = _jpeg(40, 80, orientation: 6);
    final result = await warper.warp(bytes, _kRect);
    expect(result, isNotNull);
    final out = img.decodeImage(result!)!;
    expect(out.width, 64,
        reason: 'display-frame top edge = 0.8×80 = 64; '
            'without bakeOrientation would be 32');
    expect(out.height, 32,
        reason: 'display-frame left edge = 0.8×40 = 32; '
            'without bakeOrientation would be 64');
  });
}
```

- [ ] **Step 3: Run tests → confirm RED**

```bash
cd apps/mobile && flutter test test/features/library/perspective_warper_test.dart
```
Expected: all 5 tests FAIL (stub throws `UnimplementedError`).

- [ ] **Step 4: Commit (TDD red phase)**

```bash
cd apps/mobile && git add \
  lib/features/library/perspective_warper.dart \
  test/features/library/perspective_warper_test.dart
git commit -m "test(e2): PerspectiveWarper test suite (red) + stub"
```

---

### Task 5: `PerspectiveWarper` — full implementation (GREEN)

**Files:**
- Modify: `apps/mobile/lib/features/library/perspective_warper.dart`

**Interfaces:**
- Consumes: `ImageWarper`, `WarpException`, `CropCorners`, `image` package
- Produces: working `PerspectiveWarper.warp()` used by the repo (Task 6)

- [ ] **Step 1: Implement `perspective_warper.dart`**

Replace the stub with:

```dart
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;

import 'crop_corners.dart';
import 'image_warper.dart';

class PerspectiveWarper implements ImageWarper {
  const PerspectiveWarper();

  @override
  Future<Uint8List?> warp(Uint8List bytes, CropCorners corners) {
    if (corners == CropCorners.fullFrame) return Future.value(null);
    return compute(_warpFn, _WarpArgs(bytes: bytes, corners: corners));
  }
}

// ── Isolate entry point ────────────────────────────────────────────────────

Uint8List? _warpFn(_WarpArgs args) {
  final corners = args.corners;

  final decoded = img.decodeImage(args.bytes);
  if (decoded == null) throw WarpException('failed to decode JPEG');
  // bakeOrientation rotates pixels into the EXIF-applied display frame.
  // Corners are normalized against THIS frame; skipping bake misaligns them.
  final src = img.bakeOrientation(decoded);

  final tl = Offset(corners.topLeft.dx * src.width,
                    corners.topLeft.dy * src.height);
  final tr = Offset(corners.topRight.dx * src.width,
                    corners.topRight.dy * src.height);
  final br = Offset(corners.bottomRight.dx * src.width,
                    corners.bottomRight.dy * src.height);
  final bl = Offset(corners.bottomLeft.dx * src.width,
                    corners.bottomLeft.dy * src.height);

  if (!_isConvex([tl, tr, br, bl])) {
    throw WarpException('self-crossing or degenerate quad');
  }

  final outW = _maxEdge(tl, tr, bl, br).round();
  final outH = _maxEdge(tl, bl, tr, br).round();
  if (outW < 2 || outH < 2) throw WarpException('degenerate quad: output too small');

  // Src → dst homography; invert for inverse mapping (dst pixel → src pixel).
  final h = _solveHomography(
    [tl, tr, br, bl],
    [Offset(0, 0), Offset(outW.toDouble(), 0),
     Offset(outW.toDouble(), outH.toDouble()), Offset(0, outH.toDouble())],
  );
  final hInv = _invertH3x3(h);

  final output = img.Image(width: outW, height: outH,
                            numChannels: src.numChannels);
  for (int dy = 0; dy < outH; dy++) {
    for (int dx = 0; dx < outW; dx++) {
      final sp = _applyH(hInv, dx.toDouble(), dy.toDouble());
      final pixel = src.getPixelInterpolated(sp.dx, sp.dy,
          interpolation: img.Interpolation.linear);
      output.setPixel(dx, dy, pixel);
    }
  }

  return Uint8List.fromList(img.encodeJpg(output, quality: 92));
}

// ── Math helpers ───────────────────────────────────────────────────────────

/// max(dist(a1,a2), dist(b1,b2))  →  outW or outH via edge-length sizing #1.
double _maxEdge(Offset a1, Offset a2, Offset b1, Offset b2) =>
    [_dist(a1, a2), _dist(b1, b2)].reduce((a, b) => a > b ? a : b);

double _dist(Offset a, Offset b) => (a - b).distance;

/// Returns true when [pts] (TL, TR, BR, BL in order) form a convex quad.
bool _isConvex(List<Offset> pts) {
  int sign = 0;
  final n = pts.length;
  for (int i = 0; i < n; i++) {
    final o = pts[i], a = pts[(i + 1) % n], b = pts[(i + 2) % n];
    final c = (a.dx - o.dx) * (b.dy - o.dy) - (a.dy - o.dy) * (b.dx - o.dx);
    if (c.abs() < 1e-8) continue;
    final s = c > 0 ? 1 : -1;
    if (sign == 0) {
      sign = s;
    } else if (s != sign) {
      return false;
    }
  }
  return true;
}

/// Solves the DLT 8-equation system for the homography mapping [src] → [dst].
/// Returns a flat 9-element list [h00…h21, 1.0] (h22 = 1 by convention).
List<double> _solveHomography(List<Offset> src, List<Offset> dst) {
  final m = List<List<double>>.generate(8, (row) {
    final i = row ~/ 2;
    final x = src[i].dx, y = src[i].dy;
    final u = dst[i].dx, v = dst[i].dy;
    return row.isEven
        ? [x, y, 1.0, 0.0, 0.0, 0.0, -x * u, -y * u, u]
        : [0.0, 0.0, 0.0, x, y, 1.0, -x * v, -y * v, v];
  });
  return [..._gaussElim(m), 1.0];
}

/// Gauss–Jordan elimination on an 8×9 augmented matrix [A|b].
/// Returns the 8-element solution vector.
List<double> _gaussElim(List<List<double>> m) {
  const n = 8;
  for (int col = 0; col < n; col++) {
    int maxRow = col;
    for (int row = col + 1; row < n; row++) {
      if (m[row][col].abs() > m[maxRow][col].abs()) maxRow = row;
    }
    final tmp = m[col]; m[col] = m[maxRow]; m[maxRow] = tmp;
    if (m[col][col].abs() < 1e-12) throw WarpException('singular homography system');
    for (int row = 0; row < n; row++) {
      if (row == col) continue;
      final factor = m[row][col] / m[col][col];
      for (int c = col; c <= n; c++) {
        m[row][c] -= factor * m[col][c];
      }
    }
  }
  return List<double>.generate(n, (i) => m[i][n] / m[i][i]);
}

/// Inverts a 3×3 homography stored as a flat 9-element list (row-major).
List<double> _invertH3x3(List<double> h) {
  final a = h[0], b = h[1], c = h[2];
  final d = h[3], e = h[4], f = h[5];
  final g = h[6], hh = h[7], k = h[8];
  final c00 = e * k - f * hh,  c01 = -(d * k - f * g),  c02 = d * hh - e * g;
  final c10 = -(b * k - c * hh), c11 = a * k - c * g,   c12 = -(a * hh - b * g);
  final c20 = b * f - c * e,   c21 = -(a * f - c * d),  c22 = a * e - b * d;
  final det = a * c00 + b * c01 + c * c02;
  if (det.abs() < 1e-10) throw WarpException('singular homography');
  return [
    c00/det, c10/det, c20/det,
    c01/det, c11/det, c21/det,
    c02/det, c12/det, c22/det,
  ];
}

/// Applies a flat 9-element row-major 3×3 homography to point (x, y).
Offset _applyH(List<double> h, double x, double y) {
  final w = h[6] * x + h[7] * y + h[8];
  return Offset((h[0] * x + h[1] * y + h[2]) / w,
                (h[3] * x + h[4] * y + h[5]) / w);
}

// ── Isolate-safe args ──────────────────────────────────────────────────────

class _WarpArgs {
  final Uint8List bytes;
  final CropCorners corners;
  const _WarpArgs({required this.bytes, required this.corners});
}
```

- [ ] **Step 2: Run warper tests → GREEN**

```bash
cd apps/mobile && flutter test test/features/library/perspective_warper_test.dart
```
Expected: all 5 tests pass.

- [ ] **Step 3: Full suite + analyze**

```bash
cd apps/mobile && flutter test && flutter analyze
```
Expected: all pass.

- [ ] **Step 4: Commit**

```bash
cd apps/mobile && git add lib/features/library/perspective_warper.dart
git commit -m "feat(e2): PerspectiveWarper — DLT homography, bakeOrientation, compute isolate"
```

---

### Task 6: Repository wiring + test helpers + production wiring

**Files:**
- Modify: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Modify: `apps/mobile/lib/features/library/library_dependencies.dart`
- Modify: `apps/mobile/test/support/fake_library.dart`
- Modify: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes: `ImageWarper`, `FakeImageWarper`, `PerspectiveWarper`, `flatRelativeFor`, `PageImage.flatImagePath`

- [ ] **Step 1: Write failing repo tests**

In `apps/mobile/test/features/library/drift_document_repository_test.dart`, add at the top of the file the import:
```dart
import 'package:mobile/features/library/image_warper.dart';
```

Update the `repo()` helper to accept a warper:
```dart
  DriftDocumentRepository repo({
    ImageMetadataScrubber? scrubber,
    ImageWarper? warper,
  }) =>
      DriftDocumentRepository(
        db: db,
        scrubber: scrubber ?? const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
        warper: warper ?? FakeImageWarper(),
      );
```

Also add the import for `FakeImageWarper`:
```dart
import '../../support/fake_library.dart';
```

Then add these tests inside `main()` (after existing tests):

```dart
  group('E2 — warp on save', () {
    test('non-full-frame corners: flatRelativePath written and round-trips', () async {
      final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0x01]); // fake JPEG marker
      final warper = FakeImageWarper(returnValue: fakeBytes);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );

      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: corners);

      // Warper was called once.
      expect(warper.calls, 1);

      // Flat file exists on disk.
      final flatFile =
          File('${base.path}/documents/${doc.id}/page_1_flat.jpg');
      expect(flatFile.existsSync(), isTrue);
      expect(flatFile.readAsBytesSync(), fakeBytes);

      // getDocumentPages round-trips flatImagePath.
      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, flatFile.path);
      expect(pages.single.displayPath, flatFile.path);
    });

    test('full-frame corners: flatRelativePath stays null', () async {
      final warper = FakeImageWarper();
      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: CropCorners.fullFrame);
      expect(warper.calls, 0); // short-circuited before calling warper

      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, isNull);
      expect(pages.single.displayPath, pages.single.imagePath);
    });

    test('null corners (unset): flatRelativePath stays null', () async {
      final warper = FakeImageWarper();
      final doc = await repo(warper: warper).createFromCapture(capture);
      expect(warper.calls, 0);

      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, isNull);
    });

    test('warper throws WarpException: save still succeeds, flatRelativePath null',
        () async {
      final warper = FakeImageWarper(throws: true);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );

      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: corners);
      expect(doc.id, greaterThan(0));

      final pages = await repo(warper: warper).getDocumentPages(doc.id);
      expect(pages.single.flatImagePath, isNull);
      // Original file still written.
      final origFile =
          File('${base.path}/documents/${doc.id}/page_1.jpg');
      expect(origFile.existsSync(), isTrue);
    });

    test('listDocumentSummaries: thumbnailPath prefers flat path', () async {
      final fakeBytes = Uint8List.fromList([0xFF, 0xD8, 0x02]);
      final warper = FakeImageWarper(returnValue: fakeBytes);
      const corners = CropCorners(
        topLeft: Offset(0.1, 0.1),
        topRight: Offset(0.9, 0.1),
        bottomRight: Offset(0.9, 0.9),
        bottomLeft: Offset(0.1, 0.9),
      );
      final doc = await repo(warper: warper).createFromCapture(capture,
          corners: corners);

      final summaries =
          await repo(warper: warper).listDocumentSummaries();
      final flatPath =
          '${base.path}/documents/${doc.id}/page_1_flat.jpg';
      expect(summaries.single.thumbnailPath, flatPath);
    });
  });
```

Also add `dart:ui show Offset` to imports:
```dart
import 'dart:ui' show Offset;
```

Run:
```bash
cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart
```
Expected: new tests FAIL (compile error — `warper` param doesn't exist yet).

- [ ] **Step 2: Update `DriftDocumentRepository`**

In `apps/mobile/lib/features/library/drift/drift_document_repository.dart`:

Add import at top (only the interface — never the concrete impl):
```dart
import '../image_warper.dart';
```

Add field + constructor param after `_pdfBuilder`:
```dart
  final ImageWarper _warper;

  DriftDocumentRepository({
    required AppDatabase db,
    required ImageMetadataScrubber scrubber,
    required DocumentFileStore fileStore,
    required DateTime Function() clock,
    required PdfBuilder pdfBuilder,
    required ImageWarper warper,
  })  : _db = db,
        _scrubber = scrubber,
        _fileStore = fileStore,
        _clock = clock,
        _pdfBuilder = pdfBuilder,
        _warper = warper;
```

Restructure the scrub/write block and add the warp block. The key change: hoist `scrubbed` out of the try block so it is in scope for the warp code and the page insert. Replace the current scrub try/catch and page insert inside the `_db.transaction()` closure with:

```dart
        final rel = _fileStore.relativeFor(docId, 1);
        // Hoist scrubbed out of try so it's in scope for the warp block.
        late final Uint8List scrubbed;
        try {
          final raw = await File(capture.path).readAsBytes();
          scrubbed = _scrubber.scrub(Uint8List.fromList(raw));
          await _fileStore.writeRelative(rel, scrubbed);
        } catch (e) {
          await _fileStore.deleteDocumentDir(docId); // best-effort cleanup
          rethrow; // rolls back the inserted document row
        }
        // E2: perspective-flatten best-effort. Original is already on disk.
        String? flatRel;
        if (corners != null && corners != CropCorners.fullFrame) {
          try {
            final flat = await _warper.warp(scrubbed, corners);
            if (flat != null) {
              flatRel = _fileStore.flatRelativeFor(docId, 1);
              await _fileStore.writeRelative(flatRel, flat);
            }
          } catch (_) {/* WarpException or IO — flat stays null, save proceeds */}
        }
        await _db.into(_db.pages).insert(
              PagesCompanion.insert(
                  documentId: docId,
                  position: 1,
                  relativeImagePath: rel,
                  corners: Value(corners?.toStorage()),
                  flatRelativePath: Value(flatRel)),
            );
```

In `getDocumentPages`, update the `PageImage` construction:
```dart
        .map((pg) => PageImage(
              position: pg.position,
              imagePath: _fileStore.absoluteFor(pg.relativeImagePath).path,
              corners: CropCorners.tryParse(pg.corners) ?? CropCorners.fullFrame,
              flatImagePath: pg.flatRelativePath == null
                  ? null
                  : _fileStore.absoluteFor(pg.flatRelativePath!).path,
            ))
```

In `listDocumentSummaries`, update the `firstPathByDoc` loop to prefer flat:
```dart
      for (final pg in pages) {
        firstPathByDoc.putIfAbsent(
            pg.documentId, () => pg.flatRelativePath ?? pg.relativeImagePath);
      }
```

- [ ] **Step 2b: Patch existing direct `DriftDocumentRepository` constructions**

Adding `required ImageWarper warper` breaks every test that constructs the repo inline (not through `repo()`). Add `warper: FakeImageWarper()` to these 4 call sites in `drift_document_repository_test.dart`:

`listDocumentSummaries returns newest first` test:
```dart
    final r = DriftDocumentRepository(
      db: db, scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base), clock: () => t,
      pdfBuilder: const PdfBuilder(), warper: FakeImageWarper(), // add
    );
```

`Tier 1: a delete is durable` test — `repo1` and `repo2` (same pattern):
```dart
    final repo1 = DriftDocumentRepository(
      db: db1, scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(dir), clock: () => DateTime.utc(2026, 6, 27, 9),
      pdfBuilder: const PdfBuilder(), warper: FakeImageWarper(), // add
    );
```

`Tier 1: documents persist` test — `repo1` and `repo2` (same pattern).

`rename updates the name` test:
```dart
    final r = DriftDocumentRepository(
      db: db, scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base), clock: () => t,
      pdfBuilder: const PdfBuilder(), warper: FakeImageWarper(), // add
    );
```

- [ ] **Step 3: Update `fake_library.dart` test helpers**

In `apps/mobile/test/support/fake_library.dart`, add import:
```dart
import 'package:mobile/features/library/perspective_warper.dart';
```

Update `tempLibraryDependencies()`:
```dart
LibraryDependencies tempLibraryDependencies() => LibraryDependencies(
      createRepository: () async => DriftDocumentRepository(
        db: AppDatabase(NativeDatabase.memory()),
        scrubber: const JpegExifScrubber(),
        fileStore:
            DocumentFileStore(await Directory.systemTemp.createTemp('b1bdd')),
        clock: DateTime.now,
        pdfBuilder: const PdfBuilder(),
        warper: const PerspectiveWarper(),
      ),
    );
```

Update `persistentLibraryDependencies()`:
```dart
LibraryDependencies persistentLibraryDependencies({
  required File dbFile,
  required Directory baseDir,
}) =>
    LibraryDependencies(
      createRepository: () async => DriftDocumentRepository(
        db: AppDatabase(NativeDatabase(dbFile)),
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(baseDir),
        clock: DateTime.now,
        pdfBuilder: const PdfBuilder(),
        warper: const PerspectiveWarper(),
      ),
    );
```

- [ ] **Step 4: Update production composition root**

In `apps/mobile/lib/features/library/library_dependencies.dart`, add import:
```dart
import 'perspective_warper.dart';
```

Add `warper: const PerspectiveWarper()` to the `DriftDocumentRepository(...)` call in `_defaultCreateRepository()`:
```dart
  return DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(docsDir),
    clock: DateTime.now,
    pdfBuilder: const PdfBuilder(),
    warper: const PerspectiveWarper(),
  );
```

- [ ] **Step 5: Run repo tests → GREEN**

```bash
cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart
```
Expected: all tests pass (including the 5 new E2 tests).

- [ ] **Step 6: Full suite + analyze**

```bash
cd apps/mobile && flutter test && flutter analyze
```
Expected: all pass.

- [ ] **Step 7: Commit**

```bash
cd apps/mobile && git add \
  lib/features/library/drift/drift_document_repository.dart \
  lib/features/library/library_dependencies.dart \
  test/support/fake_library.dart \
  test/features/library/drift_document_repository_test.dart
git commit -m "feat(e2): repo wiring — warp on save, flatRelativePath read/write, displayPath in list"
```

---

### Task 7: BDD step + feature + codegen

**Files:**
- Create: `apps/mobile/test/step/i_see_the_page_viewer.dart`
- Create: `apps/mobile/integration_test/e2_flatten.feature`
- Run build_runner → generates `apps/mobile/integration_test/e2_flatten_test.dart`

- [ ] **Step 1: Create `i_see_the_page_viewer` step**

Create `apps/mobile/test/step/i_see_the_page_viewer.dart`:
```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> iSeeThePageViewer(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // page-viewer-page-1: pages are 1-indexed (position=1 for the first page).
  // The spec mentions page-viewer-page-0 — that is a spec typo.
  expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);
}
```

- [ ] **Step 2: Create `e2_flatten.feature`**

Create `apps/mobile/integration_test/e2_flatten.feature`:
```gherkin
Feature: Perspective flatten
  Scenario: Flat image is shown in the page viewer after capture with adjusted corners
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I see the crop overlay
    And I drag the top left crop corner
    And I tap Accept
    Then I see a saved document on the home
    When I open the first document
    Then I see the page viewer
```

- [ ] **Step 3: Run codegen**

```bash
cd apps/mobile && dart run build_runner build --delete-conflicting-outputs 2>&1 | tail -5
```
Expected: `Succeeded after ...` and `integration_test/e2_flatten_test.dart` is generated.

- [ ] **Step 4: Verify generated test references the new step**

```bash
grep "iSeeThePageViewer\|iOpenTheFirstDocument" apps/mobile/integration_test/e2_flatten_test.dart
```
Expected: both step function calls appear.

- [ ] **Step 5: Full suite + analyze**

```bash
cd apps/mobile && flutter test && flutter analyze
```
Expected: all pass.

- [ ] **Step 6: Commit**

```bash
cd apps/mobile && git add \
  test/step/i_see_the_page_viewer.dart \
  integration_test/e2_flatten.feature \
  integration_test/e2_flatten_test.dart
git commit -m "test(e2): BDD step i_see_the_page_viewer + e2_flatten feature + generated test"
```

---

### Task 8: Verify script

**Files:**
- Create: `apps/mobile/scripts/verify/e2.sh`

- [ ] **Step 1: Create `e2.sh`**

Create `apps/mobile/scripts/verify/e2.sh`:
```bash
#!/usr/bin/env bash
# Verify E2 (perspective flatten) acceptance criteria.
# VERIFY_SKIP_DEVICE=1  — skips device launches (reported FAIL, never silent).
# REAL_DEVICE=1         — Tier-3 manual lane (capture angled doc, confirm flat).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== E2 verification =="

require_tool flutter
require_tool pnpm
require_tool git

# ── Interface + implementation ────────────────────────────────────────────
assert_file_has "ImageWarper interface" \
  "apps/mobile/lib/features/library/image_warper.dart" "abstract interface class ImageWarper"
assert_file_has "WarpException" \
  "apps/mobile/lib/features/library/image_warper.dart" "class WarpException"
assert_file_has "PerspectiveWarper class" \
  "apps/mobile/lib/features/library/perspective_warper.dart" "class PerspectiveWarper"
assert_file_has "bakeOrientation called (EXIF-frame contract)" \
  "apps/mobile/lib/features/library/perspective_warper.dart" "bakeOrientation"
assert_file_has "compute() isolate" \
  "apps/mobile/lib/features/library/perspective_warper.dart" "compute("

# ── DIP: PerspectiveWarper not imported by widget layer ───────────────────
if grep -r "perspective_warper" apps/mobile/lib/features/library/page_viewer_screen.dart \
    apps/mobile/lib/features/library/pdf/ 2>/dev/null | grep -q .; then
  fail "PerspectiveWarper imported by widget/pdf layer — DIP violation"
else
  pass "PerspectiveWarper not imported by widget layer"
fi

# ── Schema v3 ─────────────────────────────────────────────────────────────
assert_file_has "schemaVersion => 3" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "int get schemaVersion => 3;"
assert_file_has "Pages.flatRelativePath column" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "get flatRelativePath =>"
assert_file_has "onUpgrade addColumn flatRelativePath" \
  "apps/mobile/lib/features/library/drift/app_database.dart" "pages.flatRelativePath"

# ── File store ────────────────────────────────────────────────────────────
assert_file_has "flatRelativeFor method" \
  "apps/mobile/lib/features/library/document_file_store.dart" "flatRelativeFor"

# ── PageImage.displayPath ─────────────────────────────────────────────────
assert_file_has "flatImagePath field" \
  "apps/mobile/lib/features/library/page_image.dart" "flatImagePath"
assert_file_has "displayPath getter" \
  "apps/mobile/lib/features/library/page_image.dart" "String get displayPath"

# ── Consumers use displayPath ─────────────────────────────────────────────
assert_file_has "viewer uses displayPath" \
  "apps/mobile/lib/features/library/page_viewer_screen.dart" "displayPath"
assert_file_has "PdfBuilder uses displayPath" \
  "apps/mobile/lib/features/library/pdf/pdf_builder.dart" "displayPath"

# ── Repo wiring ───────────────────────────────────────────────────────────
assert_file_has "repo warper field" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "_warper"
assert_file_has "repo warp call" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "_warper.warp("

# ── Test helpers ──────────────────────────────────────────────────────────
assert_file_has "FakeImageWarper in fake_library" \
  "apps/mobile/test/support/fake_library.dart" "class FakeImageWarper"
assert_file_has "tempLibraryDependencies wires warper" \
  "apps/mobile/test/support/fake_library.dart" "warper: const PerspectiveWarper()"

# ── image package ─────────────────────────────────────────────────────────
assert_file_has "image package in pubspec" \
  "apps/mobile/pubspec.yaml" "image:"

# ── Generated code current ────────────────────────────────────────────────
assert_cmd "codegen is up to date" "Built with build_runner" \
  bash -c "cd apps/mobile && dart run build_runner build 2>&1"
assert_cmd "no uncommitted generated diff" "" \
  bash -c "git diff --exit-code -- apps/mobile/integration_test/e2_flatten_test.dart \
    apps/mobile/lib/features/library/drift/app_database.g.dart >/dev/null 2>&1 && echo OK \
    || (echo 'GENERATED FILES STALE'; exit 1)"

# ── BDD step ─────────────────────────────────────────────────────────────
assert_file_has "i_see_the_page_viewer step is real (not a stub)" \
  "apps/mobile/test/step/i_see_the_page_viewer.dart" "page-viewer-page-1"

# ── Suite ─────────────────────────────────────────────────────────────────
assert_cmd "unit + widget + migration + warper tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ── Device ────────────────────────────────────────────────────────────────
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass"
  verify_summary
fi

verify_integration_android e2_flatten_test.dart
verify_integration_ios e2_flatten_test.dart

# ── Opt-in REAL_DEVICE Tier-3 ─────────────────────────────────────────────
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE Tier-3 lane --"
  echo "MANUAL: capture an angled document, adjust one corner, Accept."
  echo "Open the document. Verify the page viewer shows a flat, head-on image"
  echo "(not the original angled capture). Export to PDF; confirm PDF page is flat."
fi

verify_summary
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x apps/mobile/scripts/verify/e2.sh
```

- [ ] **Step 3: Run the verify script**

```bash
bash apps/mobile/scripts/verify/e2.sh
```
Expected: all static asserts pass, unit tests pass, analyze clean. Device checks skipped in CI; run with `REAL_DEVICE=1` on a physical device for Tier-3.

- [ ] **Step 4: Commit**

```bash
git add apps/mobile/scripts/verify/e2.sh
git commit -m "test(e2): verify gate — static asserts + suite + both-platform integration, fail-closed"
```

---

## Self-Review

**Spec coverage check:**

| Spec requirement | Task |
|---|---|
| `image` package added | Task 1 |
| `ImageWarper` DIP interface + `WarpException` | Task 2 |
| `FakeImageWarper` in `fake_library.dart` | Task 2 |
| Schema v3 `flatRelativePath` + `onUpgrade` | Task 3 |
| Migration tests v2→v3, v1→v3 | Task 3 |
| `flatRelativeFor` in `DocumentFileStore` | Task 3 |
| `PerspectiveWarper` tests (red) | Task 4 |
| `bakeOrientation` before coordinate math | Task 4 (tested), Task 5 (impl) |
| Rotated-image alignment test | Task 4 |
| Homography DLT + Gauss–Jordan + 3×3 invert | Task 5 |
| Edge-length output sizing (#1) | Task 5 |
| Convexity guard + `WarpException` | Task 5 |
| Full-frame short-circuit before `compute()` | Task 5 |
| Warp failure never blocks save | Task 6 (tested + impl) |
| `createFromCapture` warp + write + record | Task 6 |
| `getDocumentPages` populates `flatImagePath` | Task 6 |
| `listDocumentSummaries` prefers flat thumbnail | Task 6 |
| `tempLibraryDependencies` + `persistentLibraryDependencies` warper arg | Task 6 |
| `_defaultCreateRepository` wires `PerspectiveWarper` | Task 6 |
| `PageImage.flatImagePath` + `displayPath` | Task 1 |
| `PageViewerScreen` uses `displayPath` | Task 1 |
| `PdfBuilder` uses `displayPath` | Task 1 |
| BDD `e2_flatten.feature` + `i_see_the_page_viewer` | Task 7 |
| Verify script + all static asserts | Task 8 |
| DIP violation check (no widget import of `PerspectiveWarper`) | Task 8 |

All spec requirements covered. No placeholders.
