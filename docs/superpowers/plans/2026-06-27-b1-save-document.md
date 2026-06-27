# B1 — Save Photo + Document Record Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the review screen's **Accept** persist the captured JPEG (identifying EXIF stripped, Orientation kept) to on-device storage and create a `Document`+`Page` record, surfaced as a basic name+date list on the Documents home.

**Architecture:** A `DocumentRepository` interface (DIP) with a Drift/SQLite-backed implementation that composes a pure-Dart byte-level `JpegExifScrubber`, a `DocumentFileStore` (relative↔absolute path resolution, injected base dir), and an injectable clock. A `SaveController` (ChangeNotifier, mirrors `ScanController`) drives Accept. The home becomes stateful, reads storage on entry/return, and renders the list. Spec: `docs/superpowers/specs/2026-06-27-b1-save-document-design.md`.

**Tech Stack:** Flutter, Drift/SQLite (`drift`, `sqlite3_flutter_libs`), `path_provider`, `path`; dev: `drift_dev`, `build_runner`, `exif` (test/tool only). Pure-Dart EXIF scrubber (no `image` dep at runtime).

## Global Constraints

- **Privacy spine (binding):** documents never leave the device. No network calls, no cloud. Identifying EXIF (GPS, Make, Model, Software, Serial, DateTime, MakerNote) is stripped on the first permanent write.
- **EXIF scrubber MUST be byte/segment-level**, never `package:image` decode→re-encode (that auto-orients and drops the Orientation tag — verified in the spike). Keep Orientation **losslessly** (re-emit a minimal valid Exif APP1); main scan data byte-identical.
- **Stored image paths are RELATIVE** (`documents/<docId>/page_1.jpg`), resolved against the current app documents dir at read time. Never persist an absolute path.
- **Save is transactional** (single Drift `transaction()`): a failed file write rolls back the `Document` row — no orphan rows; the capture is never lost; the user stays on review and can retry.
- **TDD/BDD first** — tests before implementation, red→green. **SOLID/KISS/DRY.** Small single-purpose files.
- **App id:** `com.camscannerlight.mobile`. **Dart SDK:** `^3.12.2`.
- **Document name:** `Scan <YYYY-MM-DD HH.MM.SS>` from an injectable clock; `createdAt`/`modifiedAt` stored as UTC.
- **SnackBar copy (exact):** `Couldn't save document. Try again.`
- **Verification harness:** silence=FAIL; assert exit codes + markers; caches disabled (`--skip-nx-cache`); the gate is `scripts/verify/b1.sh` exiting 0 with `GATE: PASS`, run independently. Coverage floor **70%** (matches A3).
- **Drift generated `*.g.dart` is committed** (same policy as the BDD generated `_test.dart`); the gate regenerates and asserts no diff.

## File Structure

**New (lib):**
- `apps/mobile/lib/features/library/document.dart` — `Document` + `Page` plain domain models.
- `apps/mobile/lib/features/library/document_repository.dart` — `DocumentRepository` interface + `DocumentSaveException`.
- `apps/mobile/lib/features/library/drift/app_database.dart` — Drift `AppDatabase` (tables `Documents`, `Pages`) + `openAppDatabase(File)`.
- `apps/mobile/lib/features/library/drift/app_database.g.dart` — generated (committed).
- `apps/mobile/lib/features/library/drift/drift_document_repository.dart` — `DriftDocumentRepository`.
- `apps/mobile/lib/features/library/document_file_store.dart` — `DocumentFileStore`.
- `apps/mobile/lib/features/library/image_metadata_scrubber.dart` — `ImageMetadataScrubber` interface + `MetadataScrubException`.
- `apps/mobile/lib/features/library/jpeg_exif_scrubber.dart` — `JpegExifScrubber` (byte-level).
- `apps/mobile/lib/features/library/save_controller.dart` — `SaveController` (`SaveStatus`).
- `apps/mobile/lib/features/library/library_dependencies.dart` — composition root.
- `apps/mobile/lib/features/library/widgets/documents_list_view.dart` — name+date list.

**Modified (lib):**
- `apps/mobile/lib/features/library/home_screen.dart` — Stateful; load list; pass repository to camera.
- `apps/mobile/lib/features/scan/camera_screen.dart` — wire Accept→`SaveController`.
- `apps/mobile/lib/features/scan/capture_review_screen.dart` — `saving` flag + disabled buttons + spinner.
- `apps/mobile/lib/main.dart` — async build repository; thread `LibraryDependencies`.
- `apps/mobile/pubspec.yaml` — deps.

**New (test/tool/infra):**
- `apps/mobile/test/fixtures/exif_sample.jpg` — **already committed with this plan** (64×64, EXIF Make=AcmeCam, Model=Model-X1, Software=fw-9.9, DateTime, Orientation=6; 6 tags).
- `apps/mobile/test/support/fake_library.dart` — fakes + temp library deps.
- `apps/mobile/test/features/library/*_test.dart` — unit/widget tests (per task).
- `apps/mobile/integration_test/b1_save_document.feature` + generated `b1_save_document_test.dart` + new `test/step/*` defs.
- `apps/mobile/tool/exif_check.dart` — host EXIF asserter for the REAL_DEVICE lane.
- `scripts/verify/b1.sh` — the gate.

---

### Task 1: Dependencies + Drift database scaffold + codegen

**Files:**
- Modify: `apps/mobile/pubspec.yaml`
- Create: `apps/mobile/lib/features/library/drift/app_database.dart`
- Generated: `apps/mobile/lib/features/library/drift/app_database.g.dart` (commit it)
- Test: `apps/mobile/test/features/library/app_database_test.dart`

**Interfaces:**
- Produces: `class AppDatabase extends _$AppDatabase { AppDatabase(QueryExecutor e); int schemaVersion == 1; }` with generated accessors `documents`, `pages`; companions `DocumentsCompanion.insert({required String name, required DateTime createdAt, required DateTime modifiedAt})`, `PagesCompanion.insert({required int documentId, required int position, required String relativeImagePath})`. Row types `Document` (Drift) and `Page` (Drift) — NOTE these are the generated row classes; the domain models in Task 4 live in a different file/namespace.
- `LazyDatabase openAppDatabase(File file)` for production; tests use `AppDatabase(NativeDatabase.memory())`.

- [ ] **Step 1: Add dependencies.** Edit `apps/mobile/pubspec.yaml`. Under `dependencies:` (after `permission_handler: ^12.0.3`) add:

```yaml
  drift: ^2.20.0
  sqlite3_flutter_libs: ^0.5.24
  path_provider: ^2.1.4
  path: ^1.9.0
```

Under `dev_dependencies:` (after `build_runner: ^2.15.0`) add:

```yaml
  drift_dev: ^2.20.0
  exif: ^3.3.0
```

Run: `cd apps/mobile && flutter pub get`
Expected: `Got dependencies!` (exit 0).

- [ ] **Step 2: Write the Drift database.** Create `apps/mobile/lib/features/library/drift/app_database.dart`:

```dart
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

part 'app_database.g.dart';

/// One scanned document's metadata. Image bytes live on disk (see Pages); this
/// table holds only metadata. `createdAt`/`modifiedAt` are stored UTC.
class Documents extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get modifiedAt => dateTime()();
}

/// One page of a document. B1 creates exactly one page (position 1). The image
/// path is RELATIVE to the app documents dir (resolved at read time) — never
/// absolute (iOS container GUID changes on reinstall/update).
class Pages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get documentId =>
      integer().references(Documents, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get relativeImagePath => text()();
}

@DriftDatabase(tables: [Documents, Pages])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        // Future columns (folderId/tags in D; corners/mode/enhancement in
        // E/F/G) bump schemaVersion and add steps here.
      );
}

/// Production opener — lazily opens the SQLite file in a background isolate.
LazyDatabase openAppDatabase(File file) =>
    LazyDatabase(() async => NativeDatabase.createInBackground(file));
```

- [ ] **Step 3: Run codegen.** Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `Succeeded` (exit 0); `lib/features/library/drift/app_database.g.dart` now exists.

- [ ] **Step 4: Write the failing round-trip test.** Create `apps/mobile/test/features/library/app_database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/drift/app_database.dart';

void main() {
  test('AppDatabase round-trips a document and a page in memory', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    final now = DateTime.utc(2026, 6, 27, 20, 26, 42);
    final docId = await db.into(db.documents).insert(
          DocumentsCompanion.insert(
              name: 'Scan 2026-06-27 20.26.42',
              createdAt: now,
              modifiedAt: now),
        );
    await db.into(db.pages).insert(
          PagesCompanion.insert(
              documentId: docId,
              position: 1,
              relativeImagePath: 'documents/$docId/page_1.jpg'),
        );

    final docs = await db.select(db.documents).get();
    final pages = await db.select(db.pages).get();
    expect(docs, hasLength(1));
    expect(docs.single.name, 'Scan 2026-06-27 20.26.42');
    expect(docs.single.createdAt, now);
    expect(pages.single.documentId, docId);
    expect(pages.single.relativeImagePath, 'documents/$docId/page_1.jpg');
  });
}
```

- [ ] **Step 5: Run the test.** Run: `cd apps/mobile && flutter test test/features/library/app_database_test.dart`
Expected: PASS (`All tests passed!`). If it fails to load SQLite on the host, the macOS/Linux system `libsqlite3` is missing — add `sqlite3: ^2.4.0` to `dependencies` (drift's native backend will use it). Re-run.

- [ ] **Step 6: Verify analyze is clean.** Run: `cd apps/mobile && flutter analyze`
Expected: `No issues found!` (the generated `.g.dart` is analyze-clean).

- [ ] **Step 7: Commit** (include the generated file).

```bash
git add apps/mobile/pubspec.yaml apps/mobile/pubspec.lock apps/mobile/lib/features/library/drift/ apps/mobile/test/features/library/app_database_test.dart
git commit -m "feat(b1): Drift AppDatabase scaffold (Documents/Pages) + codegen + round-trip test"
```

---

### Task 2: JpegExifScrubber (lossless byte-level EXIF strip, Orientation kept)

**Files:**
- Create: `apps/mobile/lib/features/library/image_metadata_scrubber.dart`
- Create: `apps/mobile/lib/features/library/jpeg_exif_scrubber.dart`
- Test: `apps/mobile/test/features/library/jpeg_exif_scrubber_test.dart`
- Uses fixture: `apps/mobile/test/fixtures/exif_sample.jpg` (committed)

**Interfaces:**
- Produces: `abstract interface class ImageMetadataScrubber { Uint8List scrub(Uint8List jpegBytes); }`, `class MetadataScrubException implements Exception`, `class JpegExifScrubber implements ImageMetadataScrubber { const JpegExifScrubber(); }`.
- Behavior: drops APP1 (Exif/XMP) and APP13 (IPTC); keeps APP0/APP2 and all coding segments byte-for-byte; re-emits a minimal Exif APP1 carrying only the original's Orientation (default 1); non-JPEG → `MetadataScrubException`.

- [ ] **Step 1: Write the interface.** Create `apps/mobile/lib/features/library/image_metadata_scrubber.dart`:

```dart
import 'dart:typed_data';

/// Strips identifying metadata from an image's bytes before it is persisted.
/// B1 ships a JPEG implementation; Feature 07 swaps in the shared scrubber.
abstract interface class ImageMetadataScrubber {
  /// Returns scrubbed bytes. Throws [MetadataScrubException] if the input is
  /// not a format this scrubber can safely process (fail closed — never write
  /// unverified data).
  Uint8List scrub(Uint8List bytes);
}

class MetadataScrubException implements Exception {
  final String message;
  const MetadataScrubException(this.message);
  @override
  String toString() => 'MetadataScrubException: $message';
}
```

- [ ] **Step 2: Write the failing test.** Create `apps/mobile/test/features/library/jpeg_exif_scrubber_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:exif/exif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/image_metadata_scrubber.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';

// Walk JPEG segments honoring lengths to find the MAIN-image SOS (0xFFDA),
// skipping APP1 and any thumbnail JPEG embedded inside it. A naive "first FFDA"
// scan would lock onto an embedded thumbnail and falsely report "differs".
int _mainSos(List<int> b) {
  var i = 2;
  while (i < b.length) {
    if (b[i] != 0xFF) {
      throw StateError('bad marker @ $i');
    }
    if (b[i + 1] == 0xDA) return i;
    final len = (b[i + 2] << 8) | b[i + 3];
    i += 2 + len;
  }
  throw StateError('no main SOS');
}

void main() {
  final scrubber = const JpegExifScrubber();
  late Uint8List sample;

  setUpAll(() {
    sample = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
  });

  test('removes identifying EXIF but keeps Orientation', () async {
    final before = await readExifFromBytes(sample);
    expect(before['Image Make'], isNotNull, reason: 'fixture sanity');
    expect(before['Image Orientation'].toString(), 'Rotated 90 CW');

    final out = scrubber.scrub(sample);
    final after = await readExifFromBytes(out);

    expect(after['Image Make'], isNull);
    expect(after['Image Model'], isNull);
    expect(after['Image Software'], isNull);
    expect(after['Image DateTime'], isNull);
    expect(after.keys.where((k) => k.startsWith('GPS')), isEmpty);
    expect(after['Image Orientation'].toString(), 'Rotated 90 CW',
        reason: 'Orientation must survive (kept losslessly)');
  });

  test('is lossless — main image scan data is byte-identical', () {
    final out = scrubber.scrub(sample);
    final a = sample.sublist(_mainSos(sample));
    final b = out.sublist(_mainSos(out));
    expect(b, equals(a));
  });

  test('throws MetadataScrubException on non-JPEG input', () {
    expect(() => scrubber.scrub(Uint8List.fromList([0, 1, 2, 3])),
        throwsA(isA<MetadataScrubException>()));
  });
}
```

- [ ] **Step 3: Run it to confirm it fails.** Run: `cd apps/mobile && flutter test test/features/library/jpeg_exif_scrubber_test.dart`
Expected: FAIL (`JpegExifScrubber` undefined).

- [ ] **Step 4: Implement the scrubber.** Create `apps/mobile/lib/features/library/jpeg_exif_scrubber.dart`:

```dart
import 'dart:typed_data';

import 'image_metadata_scrubber.dart';

/// Lossless, byte-level JPEG EXIF scrubber. Drops APP1 (Exif/XMP) and APP13
/// (Photoshop/IPTC) application segments, keeps APP0/APP2 and all coding
/// segments byte-for-byte, and re-emits a minimal canonical Exif APP1 carrying
/// ONLY the original's Orientation. Whitelist, not blacklist: nothing
/// identifying can leak. Does NOT decode/re-encode — that would auto-orient and
/// drop the tag (verified in the B1 spike).
class JpegExifScrubber implements ImageMetadataScrubber {
  const JpegExifScrubber();

  @override
  Uint8List scrub(Uint8List bytes) {
    if (bytes.length < 4 || bytes[0] != 0xFF || bytes[1] != 0xD8) {
      throw const MetadataScrubException('not a JPEG (missing SOI)');
    }
    final orientation = _readOrientation(bytes); // default 1 if absent
    final out = BytesBuilder();
    out.add([0xFF, 0xD8]); // SOI
    out.add(_minimalExifApp1(orientation));

    var i = 2;
    while (i < bytes.length) {
      if (bytes[i] != 0xFF) {
        throw const MetadataScrubException('corrupt JPEG (expected marker)');
      }
      final marker = bytes[i + 1];
      if (marker == 0xDA) {
        out.add(bytes.sublist(i)); // SOS + entropy data + EOI verbatim
        break;
      }
      if (i + 4 > bytes.length) {
        throw const MetadataScrubException('truncated JPEG segment');
      }
      final len = (bytes[i + 2] << 8) | bytes[i + 3];
      final segEnd = i + 2 + len;
      if (segEnd > bytes.length) {
        throw const MetadataScrubException('JPEG segment overruns buffer');
      }
      // Drop APP1 (0xE1: Exif/XMP) and APP13 (0xED: Photoshop/IPTC); copy the
      // rest (APP0 JFIF, APP2 ICC, DQT/DHT/SOF/...).
      if (marker != 0xE1 && marker != 0xED) {
        out.add(bytes.sublist(i, segEnd));
      }
      i = segEnd;
    }
    return out.toBytes();
  }

  /// A minimal valid Exif APP1 (big-endian TIFF, IFD0 with one Orientation
  /// SHORT, no next IFD). Validated end-to-end on-device in the B1 spike.
  List<int> _minimalExifApp1(int orientation) {
    final tiff = <int>[
      0x4D, 0x4D, 0x00, 0x2A, 0x00, 0x00, 0x00, 0x08, // 'MM', 42, IFD0 @ 8
      0x00, 0x01, // 1 entry
      0x01, 0x12, 0x00, 0x03, 0x00, 0x00, 0x00, 0x01, // Orientation, SHORT, n=1
      (orientation >> 8) & 0xFF, orientation & 0xFF, 0x00, 0x00, // value
      0x00, 0x00, 0x00, 0x00, // next IFD = 0
    ];
    final payload = <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...tiff]; // 'Exif\0\0'
    final len = payload.length + 2;
    return <int>[0xFF, 0xE1, (len >> 8) & 0xFF, len & 0xFF, ...payload];
  }

  /// Reads IFD0 Orientation (tag 0x0112) from the first APP1/Exif segment.
  /// Returns 1 if absent/unreadable (a safe default — upright).
  int _readOrientation(Uint8List b) {
    var i = 2;
    while (i + 4 <= b.length) {
      if (b[i] != 0xFF) return 1;
      final marker = b[i + 1];
      if (marker == 0xDA) return 1; // reached scan; no Exif
      final len = (b[i + 2] << 8) | b[i + 3];
      final segEnd = i + 2 + len;
      if (segEnd > b.length) return 1;
      if (marker == 0xE1 &&
          len >= 8 &&
          b[i + 4] == 0x45 && b[i + 5] == 0x78 &&
          b[i + 6] == 0x69 && b[i + 7] == 0x66) {
        return _orientationFromTiff(b, i + 4 + 6, segEnd) ?? 1;
      }
      i = segEnd;
    }
    return 1;
  }

  int? _orientationFromTiff(Uint8List b, int tiffStart, int end) {
    if (tiffStart + 8 > end) return null;
    final big = b[tiffStart] == 0x4D; // 'MM' big-endian, else 'II' little
    int u16(int o) => big ? (b[o] << 8) | b[o + 1] : (b[o + 1] << 8) | b[o];
    int u32(int o) => big
        ? (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]
        : (b[o + 3] << 24) | (b[o + 2] << 16) | (b[o + 1] << 8) | b[o];
    final ifd0 = tiffStart + u32(tiffStart + 4);
    if (ifd0 + 2 > end) return null;
    final count = u16(ifd0);
    var e = ifd0 + 2;
    for (var k = 0; k < count && e + 12 <= end; k++, e += 12) {
      if (u16(e) == 0x0112) return u16(e + 8); // Orientation value (SHORT)
    }
    return null;
  }
}
```

- [ ] **Step 5: Run the tests.** Run: `cd apps/mobile && flutter test test/features/library/jpeg_exif_scrubber_test.dart`
Expected: PASS — all 3 tests (`All tests passed!`).

- [ ] **Step 6: Commit.**

```bash
git add apps/mobile/lib/features/library/image_metadata_scrubber.dart apps/mobile/lib/features/library/jpeg_exif_scrubber.dart apps/mobile/test/features/library/jpeg_exif_scrubber_test.dart apps/mobile/test/fixtures/exif_sample.jpg
git commit -m "feat(b1): JpegExifScrubber — lossless byte-level EXIF strip, Orientation kept"
```

---

### Task 3: DocumentFileStore (relative↔absolute resolution, injected base dir)

**Files:**
- Create: `apps/mobile/lib/features/library/document_file_store.dart`
- Test: `apps/mobile/test/features/library/document_file_store_test.dart`

**Interfaces:**
- Produces: `class DocumentFileStore { DocumentFileStore(this.baseDir); final Directory baseDir; String relativeFor(int docId, int position); File absoluteFor(String relativePath); Future<void> writeRelative(String relativePath, List<int> bytes); Future<void> deleteDocumentDir(int docId); }`.

- [ ] **Step 1: Write the failing test.** Create `apps/mobile/test/features/library/document_file_store_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory base;
  setUp(() => base = Directory.systemTemp.createTempSync('b1fs'));
  tearDown(() {
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test('relativeFor builds a stable relative path (no leading slash)', () {
    final store = DocumentFileStore(base);
    expect(store.relativeFor(7, 1), 'documents/7/page_1.jpg');
  });

  test('writeRelative creates dirs and writes bytes', () async {
    final store = DocumentFileStore(base);
    final rel = store.relativeFor(7, 1);
    await store.writeRelative(rel, [1, 2, 3]);
    final f = File(p.join(base.path, rel));
    expect(f.existsSync(), isTrue);
    expect(f.readAsBytesSync(), [1, 2, 3]);
  });

  test('absoluteFor resolves the SAME relative path under a CHANGED base '
      '(iOS container-GUID safety)', () async {
    final store = DocumentFileStore(base);
    final rel = store.relativeFor(7, 1);
    await store.writeRelative(rel, [9]);

    // Simulate the container moving: copy the tree to a new base, resolve there.
    final base2 = Directory.systemTemp.createTempSync('b1fs2');
    addTearDown(() => base2.deleteSync(recursive: true));
    final src = File(p.join(base.path, rel));
    final dst = File(p.join(base2.path, rel))..parent.createSync(recursive: true);
    dst.writeAsBytesSync(src.readAsBytesSync());

    final store2 = DocumentFileStore(base2);
    expect(store2.absoluteFor(rel).existsSync(), isTrue,
        reason: 'relative path must resolve under the new base');
  });

  test('deleteDocumentDir removes the per-document directory', () async {
    final store = DocumentFileStore(base);
    await store.writeRelative(store.relativeFor(7, 1), [1]);
    await store.deleteDocumentDir(7);
    expect(Directory(p.join(base.path, 'documents', '7')).existsSync(), isFalse);
  });
}
```

- [ ] **Step 2: Run it to confirm it fails.** Run: `cd apps/mobile && flutter test test/features/library/document_file_store_test.dart` → FAIL (undefined).

- [ ] **Step 3: Implement.** Create `apps/mobile/lib/features/library/document_file_store.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;

/// Resolves relative image paths against an injected base directory and owns
/// per-document file IO. The base dir is INJECTED (the composition root calls
/// `path_provider` once and passes it in) — never fetched internally, so host
/// unit tests can pass a temp dir.
class DocumentFileStore {
  final Directory baseDir;
  const DocumentFileStore(this.baseDir);

  String relativeFor(int docId, int position) =>
      'documents/$docId/page_$position.jpg';

  File absoluteFor(String relativePath) =>
      File(p.join(baseDir.path, relativePath));

  Future<void> writeRelative(String relativePath, List<int> bytes) async {
    final f = absoluteFor(relativePath);
    await f.parent.create(recursive: true);
    await f.writeAsBytes(bytes, flush: true);
  }

  Future<void> deleteDocumentDir(int docId) async {
    final dir = Directory(p.join(baseDir.path, 'documents', '$docId'));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
```

- [ ] **Step 4: Run the tests.** Run: `cd apps/mobile && flutter test test/features/library/document_file_store_test.dart` → PASS.

- [ ] **Step 5: Commit.**

```bash
git add apps/mobile/lib/features/library/document_file_store.dart apps/mobile/test/features/library/document_file_store_test.dart
git commit -m "feat(b1): DocumentFileStore — injected base dir, relative-path resolution"
```

---

### Task 4: Domain models + DocumentRepository interface + DriftDocumentRepository

**Files:**
- Create: `apps/mobile/lib/features/library/document.dart`
- Create: `apps/mobile/lib/features/library/document_repository.dart`
- Create: `apps/mobile/lib/features/library/drift/drift_document_repository.dart`
- Test: `apps/mobile/test/features/library/drift_document_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase` (Task 1), `ImageMetadataScrubber` (Task 2), `DocumentFileStore` (Task 3), `CapturedImage` (`apps/mobile/lib/features/scan/captured_image.dart`, has `.path`).
- Produces:
  - `class Document { final int id; final String name; final DateTime createdAt; final DateTime modifiedAt; const Document(...); }` and `class Page { final int id; final int documentId; final int position; final String relativeImagePath; const Page(...); }` (plain domain models, distinct from Drift rows).
  - `abstract interface class DocumentRepository { Future<Document> createFromCapture(CapturedImage capture); Future<List<Document>> listDocuments(); }` + `class DocumentSaveException implements Exception`.
  - `class DriftDocumentRepository implements DocumentRepository { DriftDocumentRepository({required AppDatabase db, required ImageMetadataScrubber scrubber, required DocumentFileStore fileStore, required DateTime Function() clock}); }`.

- [ ] **Step 1: Write the domain models.** Create `apps/mobile/lib/features/library/document.dart`:

```dart
/// Plain domain model for a saved document (decoupled from Drift row types).
class Document {
  final int id;
  final String name;
  final DateTime createdAt; // UTC
  final DateTime modifiedAt; // UTC
  const Document({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.modifiedAt,
  });
}

/// Plain domain model for one page. [relativeImagePath] is relative to the app
/// documents dir (resolved at read time).
class Page {
  final int id;
  final int documentId;
  final int position;
  final String relativeImagePath;
  const Page({
    required this.id,
    required this.documentId,
    required this.position,
    required this.relativeImagePath,
  });
}
```

- [ ] **Step 2: Write the repository interface.** Create `apps/mobile/lib/features/library/document_repository.dart`:

```dart
import '../scan/captured_image.dart';
import 'document.dart';

/// The only persistence surface the widget layer knows (DIP). The Drift
/// implementation hides the DB, scrubber, file store, and clock.
abstract interface class DocumentRepository {
  /// Persists [capture] (EXIF-scrubbed) and creates a one-page document.
  /// Throws [DocumentSaveException] on any failure (the capture is not lost).
  Future<Document> createFromCapture(CapturedImage capture);

  /// All documents, newest first.
  Future<List<Document>> listDocuments();
}

class DocumentSaveException implements Exception {
  final String message;
  const DocumentSaveException(this.message);
  @override
  String toString() => 'DocumentSaveException: $message';
}
```

- [ ] **Step 3: Write the failing test.** Create `apps/mobile/test/features/library/drift_document_repository_test.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/image_metadata_scrubber.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// A scrubber that throws — to drive the crash-safety rollback test.
class _ThrowingScrubber implements ImageMetadataScrubber {
  @override
  Uint8List scrub(Uint8List bytes) => throw const MetadataScrubException('boom');
}

void main() {
  late Directory base;
  late AppDatabase db;
  late CapturedImage capture;
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('b1repo');
    db = AppDatabase(NativeDatabase.memory());
    // a real captured temp file (use the committed EXIF fixture bytes)
    final src = File('${base.path}/cap.jpg')
      ..writeAsBytesSync(File('test/fixtures/exif_sample.jpg').readAsBytesSync());
    capture = CapturedImage(src.path);
  });
  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  DriftDocumentRepository repo({ImageMetadataScrubber? scrubber}) =>
      DriftDocumentRepository(
        db: db,
        scrubber: scrubber ?? const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
      );

  test('createFromCapture writes a scrubbed JPEG and a document+page row',
      () async {
    final doc = await repo().createFromCapture(capture);

    expect(doc.name, 'Scan 2026-06-27 20.26.42');
    expect(doc.createdAt, DateTime.utc(2026, 6, 27, 20, 26, 42));

    final file = File('${base.path}/documents/${doc.id}/page_1.jpg');
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(0));

    final pages = await db.select(db.pages).get();
    expect(pages.single.relativeImagePath, 'documents/${doc.id}/page_1.jpg');
    expect(pages.single.relativeImagePath.startsWith('/'), isFalse,
        reason: 'path MUST be relative, never absolute');
  });

  test('listDocuments returns newest first', () async {
    var t = DateTime.utc(2026, 6, 27, 10);
    final r = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: () => t,
    );
    await r.createFromCapture(capture);
    t = DateTime.utc(2026, 6, 27, 12);
    await r.createFromCapture(capture);

    final docs = await r.listDocuments();
    expect(docs, hasLength(2));
    expect(docs.first.createdAt.isAfter(docs.last.createdAt), isTrue);
  });

  test('a failed write rolls back — no orphan document row, no dir', () async {
    await expectLater(
      repo(scrubber: _ThrowingScrubber()).createFromCapture(capture),
      throwsA(isA<DocumentSaveException>()),
    );
    expect(await db.select(db.documents).get(), isEmpty,
        reason: 'transaction must roll the row back');
    expect(Directory('${base.path}/documents').existsSync(), isFalse);
  });
}
```

- [ ] **Step 4: Run it to confirm it fails.** Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart` → FAIL (undefined).

- [ ] **Step 5: Implement.** Create `apps/mobile/lib/features/library/drift/drift_document_repository.dart`:

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart';

import '../../scan/captured_image.dart';
import '../document.dart';
import '../document_file_store.dart';
import '../document_repository.dart';
import '../image_metadata_scrubber.dart';
import 'app_database.dart';

/// Drift-backed [DocumentRepository]. Scrubs the capture, writes the file, and
/// inserts the rows inside a single transaction so the DB never holds a partial
/// record. Stores RELATIVE image paths.
class DriftDocumentRepository implements DocumentRepository {
  final AppDatabase _db;
  final ImageMetadataScrubber _scrubber;
  final DocumentFileStore _fileStore;
  final DateTime Function() _clock;

  DriftDocumentRepository({
    required AppDatabase db,
    required ImageMetadataScrubber scrubber,
    required DocumentFileStore fileStore,
    required DateTime Function() clock,
  })  : _db = db,
        _scrubber = scrubber,
        _fileStore = fileStore,
        _clock = clock;

  @override
  Future<Document> createFromCapture(CapturedImage capture) async {
    final now = _clock();
    final createdUtc = now.toUtc();
    final name = _defaultName(now);
    try {
      final doc = await _db.transaction(() async {
        final docId = await _db.into(_db.documents).insert(
              DocumentsCompanion.insert(
                  name: name, createdAt: createdUtc, modifiedAt: createdUtc),
            );
        final rel = _fileStore.relativeFor(docId, 1);
        try {
          final raw = await File(capture.path).readAsBytes();
          final scrubbed = _scrubber.scrub(Uint8List.fromList(raw));
          await _fileStore.writeRelative(rel, scrubbed);
        } catch (e) {
          await _fileStore.deleteDocumentDir(docId); // best-effort cleanup
          rethrow; // rolls back the inserted document row
        }
        await _db.into(_db.pages).insert(
              PagesCompanion.insert(
                  documentId: docId, position: 1, relativeImagePath: rel),
            );
        return Document(
            id: docId,
            name: name,
            createdAt: createdUtc,
            modifiedAt: createdUtc);
      });
      await _deleteTempSource(capture.path);
      return doc;
    } catch (e) {
      throw DocumentSaveException('save failed: $e');
    }
  }

  @override
  Future<List<Document>> listDocuments() async {
    final rows = await (_db.select(_db.documents)
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
        .get();
    return rows
        .map((r) => Document(
            id: r.id,
            name: r.name,
            createdAt: r.createdAt,
            modifiedAt: r.modifiedAt))
        .toList();
  }

  String _defaultName(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Scan ${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}.${two(t.minute)}.${two(t.second)}';
  }

  Future<void> _deleteTempSource(String path) async {
    try {
      final f = File(path);
      if (await f.exists() && path.contains(Directory.systemTemp.path)) {
        await f.delete();
      }
    } catch (_) {/* best-effort */}
  }
}
```

- [ ] **Step 6: Run the tests.** Run: `cd apps/mobile && flutter test test/features/library/drift_document_repository_test.dart` → PASS (all 3).

- [ ] **Step 7: Commit.**

```bash
git add apps/mobile/lib/features/library/document.dart apps/mobile/lib/features/library/document_repository.dart apps/mobile/lib/features/library/drift/drift_document_repository.dart apps/mobile/test/features/library/drift_document_repository_test.dart
git commit -m "feat(b1): DriftDocumentRepository — transactional save, relative paths, newest-first"
```

---

### Task 5: SaveController (idle → saving → error)

**Files:**
- Create: `apps/mobile/lib/features/library/save_controller.dart`
- Create: `apps/mobile/test/support/fake_library.dart`
- Test: `apps/mobile/test/features/library/save_controller_test.dart`

**Interfaces:**
- Consumes: `DocumentRepository`, `Document`, `CapturedImage`.
- Produces: `enum SaveStatus { idle, saving, error }`, `class SaveController extends ChangeNotifier { SaveController({required DocumentRepository repository}); SaveStatus get status; bool get saving; Future<Document?> save(CapturedImage image); }`.
- Also produces (fake_library.dart): `class FakeDocumentRepository implements DocumentRepository` with `int createCalls`, optional `bool throwOnCreate`, an optional gate `Completer<void>? gate`, and a seedable `List<Document> documents`.

- [ ] **Step 1: Write the test fakes.** Create `apps/mobile/test/support/fake_library.dart`:

```dart
import 'dart:async';

import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// In-memory fake repository for host tests. Optionally throws, or blocks on a
/// [gate] so a test can observe the transient `saving` state.
class FakeDocumentRepository implements DocumentRepository {
  final bool throwOnCreate;
  final Completer<void>? gate;
  final List<Document> documents;
  int createCalls = 0;

  FakeDocumentRepository({
    this.throwOnCreate = false,
    this.gate,
    List<Document>? documents,
  }) : documents = documents ?? <Document>[];

  @override
  Future<Document> createFromCapture(CapturedImage capture) async {
    createCalls++;
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

  @override
  Future<List<Document>> listDocuments() async =>
      List<Document>.unmodifiable(documents);
}
```

- [ ] **Step 2: Write the failing test.** Create `apps/mobile/test/features/library/save_controller_test.dart`:

```dart
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/save_controller.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

void main() {
  const img = CapturedImage('/tmp/cap.jpg');

  test('save() toggles saving and returns the document on success', () async {
    final repo = FakeDocumentRepository();
    final c = SaveController(repository: repo);
    final states = <SaveStatus>[];
    c.addListener(() => states.add(c.status));

    final doc = await c.save(img);

    expect(doc, isNotNull);
    expect(repo.createCalls, 1);
    expect(c.status, SaveStatus.idle);
    expect(states, containsAllInOrder([SaveStatus.saving, SaveStatus.idle]));
  });

  test('save() goes to error and returns null on failure', () async {
    final c = SaveController(repository: FakeDocumentRepository(throwOnCreate: true));
    final doc = await c.save(img);
    expect(doc, isNull);
    expect(c.status, SaveStatus.error);
  });

  test('a second save while one is in flight is ignored', () async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(gate: gate);
    final c = SaveController(repository: repo);

    final first = c.save(img);
    final second = await c.save(img); // in-flight → ignored
    expect(second, isNull);
    expect(repo.createCalls, 1);

    gate.complete();
    expect(await first, isNotNull);
    expect(c.saving, isFalse);
  });

  test('disposing mid-save does not notify after dispose', () async {
    final gate = Completer<void>();
    final c = SaveController(repository: FakeDocumentRepository(gate: gate));
    var notifications = 0;
    c.addListener(() => notifications++);

    // ignore: unawaited_futures
    c.save(img);
    await Future<void>.value();
    final at = notifications;
    c.dispose();
    gate.complete();
    await Future<void>.value();
    expect(notifications, at, reason: 'no notifyListeners() after dispose');
  });
}
```

- [ ] **Step 3: Run it to confirm it fails.** Run: `cd apps/mobile && flutter test test/features/library/save_controller_test.dart` → FAIL.

- [ ] **Step 4: Implement.** Create `apps/mobile/lib/features/library/save_controller.dart`:

```dart
import 'package:flutter/foundation.dart';

import '../scan/captured_image.dart';
import 'document.dart';
import 'document_repository.dart';

enum SaveStatus { idle, saving, error }

/// Drives the review screen's Accept action. Mirrors `ScanController`: a small
/// state machine with a double-tap guard and dispose-safety. Holds no widgets.
class SaveController extends ChangeNotifier {
  final DocumentRepository _repository;
  SaveController({required DocumentRepository repository})
      : _repository = repository;

  SaveStatus _status = SaveStatus.idle;
  SaveStatus get status => _status;
  bool get saving => _status == SaveStatus.saving;

  bool _disposed = false;

  /// Persists [image]. Returns the saved [Document], or null if not saved
  /// (already saving, disposed, or the save failed — caller surfaces failure).
  Future<Document?> save(CapturedImage image) async {
    if (_disposed || _status == SaveStatus.saving) return null;
    _set(SaveStatus.saving);
    try {
      final doc = await _repository.createFromCapture(image);
      if (_disposed) return null;
      _set(SaveStatus.idle);
      return doc;
    } catch (_) {
      if (_disposed) return null;
      _set(SaveStatus.error);
      return null;
    }
  }

  void _set(SaveStatus status) {
    if (_disposed) return;
    _status = status;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
```

- [ ] **Step 5: Run the tests.** Run: `cd apps/mobile && flutter test test/features/library/save_controller_test.dart` → PASS.

- [ ] **Step 6: Commit.**

```bash
git add apps/mobile/lib/features/library/save_controller.dart apps/mobile/test/support/fake_library.dart apps/mobile/test/features/library/save_controller_test.dart
git commit -m "feat(b1): SaveController (idle/saving/error) + FakeDocumentRepository"
```

---

### Task 6: LibraryDependencies + DocumentsListView + stateful HomeScreen + app wiring

**Files:**
- Create: `apps/mobile/lib/features/library/library_dependencies.dart`
- Create: `apps/mobile/lib/features/library/widgets/documents_list_view.dart`
- Modify: `apps/mobile/lib/features/library/home_screen.dart`
- Modify: `apps/mobile/lib/main.dart`
- Test: `apps/mobile/test/features/library/documents_list_view_test.dart`
- Modify test: `apps/mobile/test/features/library/home_screen_test.dart`

**Interfaces:**
- Consumes: `DocumentRepository`, `Document`, `DriftDocumentRepository`, `AppDatabase`, `JpegExifScrubber`, `DocumentFileStore`.
- Produces:
  - `typedef DocumentRepositoryFactory = Future<DocumentRepository> Function();`
  - `class LibraryDependencies { final DocumentRepositoryFactory createRepository; const LibraryDependencies({this.createRepository = _defaultCreateRepository}); }`
  - `class DocumentsListView extends StatelessWidget { const DocumentsListView({super.key, required this.documents}); final List<Document> documents; }` — renders a `ListView` keyed `Key('documents-list')`, each row a `ListTile` keyed `Key('document-tile-<id>')` with the name as title and the formatted local date as subtitle.
  - `HomeScreen({Key? key, ScanDependencies dependencies, LibraryDependencies libraryDependencies})`.

- [ ] **Step 1: Write LibraryDependencies.** Create `apps/mobile/lib/features/library/library_dependencies.dart`:

```dart
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'document_file_store.dart';
import 'document_repository.dart';
import 'drift/app_database.dart';
import 'drift/drift_document_repository.dart';
import 'jpeg_exif_scrubber.dart';

typedef DocumentRepositoryFactory = Future<DocumentRepository> Function();

/// Composition root for the Library feature (parallel to ScanDependencies).
/// Production builds a Drift-backed repository; tests inject a fake factory.
class LibraryDependencies {
  final DocumentRepositoryFactory createRepository;
  const LibraryDependencies({this.createRepository = _defaultCreateRepository});
}

Future<DocumentRepository> _defaultCreateRepository() async {
  final docsDir = await getApplicationDocumentsDirectory();
  final supportDir = await getApplicationSupportDirectory();
  final dbFile = File(p.join(supportDir.path, 'camscanner.sqlite'));
  final db = AppDatabase(openAppDatabase(dbFile));
  return DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(docsDir),
    clock: DateTime.now,
  );
}
```

- [ ] **Step 2: Write the failing DocumentsListView test.** Create `apps/mobile/test/features/library/documents_list_view_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

void main() {
  Document doc(int id) => Document(
        id: id,
        name: 'Scan 2026-06-27 20.26.42',
        createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
      );

  testWidgets('renders one tile per document with name + date', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: DocumentsListView(documents: [doc(1), doc(2)])),
    ));
    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-1')), findsOneWidget);
    expect(find.byKey(const Key('document-tile-2')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsNWidgets(2));
  });
}
```

- [ ] **Step 3: Implement DocumentsListView.** Create `apps/mobile/lib/features/library/widgets/documents_list_view.dart`:

```dart
import 'package:flutter/material.dart';

import '../document.dart';

/// Basic name + date list of saved documents (B1). No thumbnails — that is B2,
/// and rendering local image files here would risk the Image.file host-test
/// hang. Newest first (the repository orders the list).
class DocumentsListView extends StatelessWidget {
  final List<Document> documents;
  const DocumentsListView({super.key, required this.documents});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      key: const Key('documents-list'),
      itemCount: documents.length,
      itemBuilder: (context, i) {
        final d = documents[i];
        return ListTile(
          key: Key('document-tile-${d.id}'),
          leading: const Icon(Icons.description_outlined),
          title: Text(d.name),
          subtitle: Text(_formatLocal(d.createdAt.toLocal())),
        );
      },
    );
  }

  String _formatLocal(DateTime t) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${t.year}-${two(t.month)}-${two(t.day)} '
        '${two(t.hour)}:${two(t.minute)}';
  }
}
```

- [ ] **Step 4: Run the list test.** Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart` → PASS.

- [ ] **Step 5: Rewrite HomeScreen as stateful.** Replace the entire contents of `apps/mobile/lib/features/library/home_screen.dart`:

```dart
import 'package:flutter/material.dart';

import '../scan/camera_screen.dart';
import '../scan/scan_dependencies.dart';
import 'document.dart';
import 'document_repository.dart';
import 'library_dependencies.dart';
import 'widgets/documents_list_view.dart';
import 'widgets/empty_documents_view.dart';

/// The app's home: the document library. Builds the repository, lists saved
/// documents (name + date), and opens the camera. Reloads the list whenever the
/// camera flow returns (a save may have happened).
class HomeScreen extends StatefulWidget {
  final ScanDependencies dependencies;
  final LibraryDependencies libraryDependencies;

  const HomeScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DocumentRepository? _repository;
  List<Document> _documents = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final repo = await widget.libraryDependencies.createRepository();
    if (!mounted) return;
    _repository = repo;
    await _load();
  }

  Future<void> _load() async {
    final repo = _repository;
    if (repo == null) return;
    final docs = await repo.listDocuments();
    if (!mounted) return;
    setState(() {
      _documents = docs;
      _loading = false;
    });
  }

  Future<void> _openScan() async {
    final repo = _repository;
    if (repo == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            CameraScreen(dependencies: widget.dependencies, repository: repo),
      ),
    );
    await _load(); // a save may have happened while we were away
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Documents')),
      body: _loading
          ? const Center(
              key: Key('documents-loading'),
              child: CircularProgressIndicator())
          : _documents.isEmpty
              ? const EmptyDocumentsView()
              : DocumentsListView(documents: _documents),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _repository == null ? null : _openScan,
        icon: const Icon(Icons.document_scanner_outlined),
        label: const Text('Scan'),
      ),
    );
  }
}
```

- [ ] **Step 6: Update main.dart to build the repository.** Replace the contents of `apps/mobile/lib/main.dart`:

```dart
import 'package:flutter/material.dart';

import 'features/library/home_screen.dart';
import 'features/library/library_dependencies.dart';
import 'features/scan/scan_dependencies.dart';

void main() => runCamScannerApp();

/// App entrypoint with injectable Scan + Library dependencies, so integration
/// tests can drive deterministic states on a real device.
void runCamScannerApp({
  ScanDependencies scanDependencies = const ScanDependencies(),
  LibraryDependencies libraryDependencies = const LibraryDependencies(),
}) {
  runApp(CamScannerApp(
    scanDependencies: scanDependencies,
    libraryDependencies: libraryDependencies,
  ));
}

class CamScannerApp extends StatelessWidget {
  final ScanDependencies scanDependencies;
  final LibraryDependencies libraryDependencies;

  const CamScannerApp({
    super.key,
    this.scanDependencies = const ScanDependencies(),
    this.libraryDependencies = const LibraryDependencies(),
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CamScanner-light',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      home: HomeScreen(
        dependencies: scanDependencies,
        libraryDependencies: libraryDependencies,
      ),
    );
  }
}
```

- [ ] **Step 7: Update home_screen_test.dart to inject a fake library + provide a `fakeLibraryDeps` helper.** First add to `apps/mobile/test/support/fake_library.dart` (append):

```dart
import 'package:mobile/features/library/library_dependencies.dart';

/// LibraryDependencies whose factory returns the given fake repository.
LibraryDependencies fakeLibraryDependencies(FakeDocumentRepository repo) =>
    LibraryDependencies(createRepository: () async => repo);
```

(keep the existing imports; add the one above near the top.)

Then replace `apps/mobile/test/features/library/home_screen_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, FakeDocumentRepository repo) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(repo),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Documents app bar title', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no documents',
      (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('lists saved documents when storage is non-empty',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [
      Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
    ]);
    await pumpHome(tester, repo);
    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsOneWidget);
    expect(find.text('No documents yet'), findsNothing);
  });

  testWidgets('shows a tappable Scan button once loaded', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    final fab = tester.widget<FloatingActionButton>(
      find.widgetWithText(FloatingActionButton, 'Scan'),
    );
    expect(fab.onPressed, isNotNull);
  });

  testWidgets('tapping Scan opens the camera screen', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  });
}
```

NOTE: `tapping Scan opens the camera screen` requires `CameraScreen` to accept a `repository` (Task 7). Until Task 7 lands this single test will not compile — that is expected ordering; run the other tests in this task in isolation (Step 8) and the full file after Task 7.

- [ ] **Step 8: Run the list + home tests that don't depend on Task 7.** Run: `cd apps/mobile && flutter test test/features/library/documents_list_view_test.dart` → PASS. (The home_screen test's Scan-opens-camera case compiles after Task 7; the others are exercised in the full suite then.)

- [ ] **Step 9: Verify analyze.** Run: `cd apps/mobile && flutter analyze` → `No issues found!` (the home test referencing `CameraScreen(repository:)` will analyze-error until Task 7 — acceptable mid-task; if blocking, temporarily land Task 7's `CameraScreen` signature first. The reviewer gate for this task runs after Task 7's signature exists.)

- [ ] **Step 10: Commit.**

```bash
git add apps/mobile/lib/features/library/library_dependencies.dart apps/mobile/lib/features/library/widgets/documents_list_view.dart apps/mobile/lib/features/library/home_screen.dart apps/mobile/lib/main.dart apps/mobile/test/features/library/documents_list_view_test.dart apps/mobile/test/features/library/home_screen_test.dart apps/mobile/test/support/fake_library.dart
git commit -m "feat(b1): LibraryDependencies + DocumentsListView + stateful HomeScreen reading storage"
```

> **Controller note:** Tasks 6 and 7 are mutually referential at the `CameraScreen` signature (Home passes `repository:`; Camera consumes it). Dispatch Task 6 then Task 7 back-to-back, and run the **combined** test+analyze gate (Task 7 Step 7) before marking either complete. If the reviewer prefers a single reviewable unit, merge 6+7.

---

### Task 7: Wire Accept → save (camera screen + review screen saving state)

**Files:**
- Modify: `apps/mobile/lib/features/scan/camera_screen.dart`
- Modify: `apps/mobile/lib/features/scan/capture_review_screen.dart`
- Test: `apps/mobile/test/features/scan/capture_review_screen_test.dart` (extend)
- Modify test: `apps/mobile/test/features/scan/camera_screen_capture_test.dart`

**Interfaces:**
- Consumes: `SaveController`, `DocumentRepository`, `CapturedImage`.
- Produces: `CameraScreen({..., required DocumentRepository repository})`; `CaptureReviewScreen({..., bool saving = false})` with buttons disabled + a spinner (`Key('review-saving')`) while saving.

- [ ] **Step 1: Add the saving state to CaptureReviewScreen.** Edit `apps/mobile/lib/features/scan/capture_review_screen.dart`. Add a `final bool saving;` field (default `false`) to the constructor, gate the buttons, and overlay a spinner. Replace the `bottomNavigationBar` Row's two buttons' `onPressed` and add the overlay:

```dart
// constructor: add `this.saving = false,`
//   final bool saving;
// In the body Stack, after the Center(child: Image.file(...)), add when saving:
//   if (saving) const ColoredBox(
//     color: Colors.black54,
//     child: Center(child: CircularProgressIndicator(key: Key('review-saving'))),
//   ),
// Buttons:
//   OutlinedButton.icon(key: Key('review-retake'), onPressed: saving ? null : onRetake, ...)
//   FilledButton.icon(key: Key('review-accept'), onPressed: saving ? null : onAccept, ...)
```

Full replacement of the `build` method body (keep imports + field additions):

```dart
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Review')),
      body: Stack(
        children: [
          ColoredBox(
            color: Colors.black,
            child: Center(
              child: Image.file(
                File(image.path),
                key: const Key('review-image'),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stack) => const Icon(
                  Icons.broken_image_outlined,
                  key: Key('review-image-error'),
                  color: Colors.white54,
                  size: 64,
                ),
              ),
            ),
          ),
          if (saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Colors.black54,
                child: Center(
                  child:
                      CircularProgressIndicator(key: Key('review-saving')),
                ),
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
                onPressed: saving ? null : onRetake,
                icon: const Icon(Icons.replay),
                label: const Text('Retake'),
              ),
              FilledButton.icon(
                key: const Key('review-accept'),
                onPressed: saving ? null : onAccept,
                icon: const Icon(Icons.check),
                label: const Text('Accept'),
              ),
            ],
          ),
        ),
      ),
    );
  }
```

Add the field to the constructor:

```dart
  final CapturedImage image;
  final VoidCallback onRetake;
  final VoidCallback onAccept;
  final bool saving;

  const CaptureReviewScreen({
    super.key,
    required this.image,
    required this.onRetake,
    required this.onAccept,
    this.saving = false,
  });
```

- [ ] **Step 2: Wire CameraScreen.** Edit `apps/mobile/lib/features/scan/camera_screen.dart`:
  - Add imports: `import '../library/document_repository.dart';`, `import '../library/save_controller.dart';`.
  - Add `final DocumentRepository repository;` and require it in the constructor.
  - Build `late final SaveController _saveController;` in `initState` (`_saveController = SaveController(repository: widget.repository);`) and `_saveController.dispose()` in `dispose`.
  - Replace `_onShutter`'s push so the review screen listens to the save controller and Accept saves:

```dart
  Future<void> _onShutter() async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final image = await _controller.capture();
    if (!mounted) return;
    if (image == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not capture photo. Try again.')),
      );
      return;
    }
    await navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => ListenableBuilder(
          listenable: _saveController,
          builder: (context, _) => CaptureReviewScreen(
            image: image,
            saving: _saveController.saving,
            onRetake: navigator.pop,
            onAccept: () => _onAccept(image),
          ),
        ),
      ),
    );
  }

  Future<void> _onAccept(CapturedImage image) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final doc = await _saveController.save(image);
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

  Add `import 'captured_image.dart';` if not already present, and the constructor:

```dart
  const CameraScreen({
    super.key,
    this.dependencies = const ScanDependencies(),
    required this.repository,
  });
```

- [ ] **Step 3: Update the A3 camera capture tests to provide a repository.** Edit `apps/mobile/test/features/scan/camera_screen_capture_test.dart`:
  - Add `import '../../support/fake_library.dart';`.
  - Every `CameraScreen(dependencies: ...)` construction gets `repository: FakeDocumentRepository()` added.
  - Add a new test for the save-failure path:

```dart
  testWidgets('Accept save failure shows a SnackBar and stays on review',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: _grantedReview(),
        repository: FakeDocumentRepository(throwOnCreate: true),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pump(); // start save
    await tester.pump(const Duration(milliseconds: 50)); // let it fail
    expect(find.text("Couldn't save document. Try again."), findsOneWidget);
    expect(find.byKey(const Key('review-accept')), findsOneWidget,
        reason: 'still on the review screen');
  });

  testWidgets('Accept save success returns to the Documents home',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CameraScreen(
        dependencies: _grantedReview(),
        repository: FakeDocumentRepository(),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scan-shutter')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-accept')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('review-accept')), findsNothing,
        reason: 'left the review screen after a successful save');
  });
```

  (The existing `_grantedReview()` helper returns `ScanDependencies` with `captureReturnPath: '/nonexistent/capture.jpg'`; keep using it. The non-loadable path keeps the review host test from hanging on `Image.file`.)

- [ ] **Step 4: Extend the review screen test for the saving state.** Add to `apps/mobile/test/features/scan/capture_review_screen_test.dart`:

```dart
  testWidgets('saving disables buttons and shows the spinner', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/x.jpg'),
        onRetake: () {},
        onAccept: () {},
        saving: true,
      ),
    ));
    expect(find.byKey(const Key('review-saving')), findsOneWidget);
    final accept = tester.widget<FilledButton>(
        find.byKey(const Key('review-accept')));
    expect(accept.onPressed, isNull);
  });
```

  (Ensure the test file imports `CapturedImage` and `CaptureReviewScreen`.)

- [ ] **Step 5: Run the affected tests.** Run: `cd apps/mobile && flutter test test/features/scan/capture_review_screen_test.dart test/features/scan/camera_screen_capture_test.dart test/features/library/home_screen_test.dart` → PASS.

- [ ] **Step 6: Run the full unit/widget suite + analyze.** Run: `cd apps/mobile && flutter test` then `flutter analyze`
Expected: `All tests passed!` and `No issues found!`.

- [ ] **Step 7: Commit.**

```bash
git add apps/mobile/lib/features/scan/camera_screen.dart apps/mobile/lib/features/scan/capture_review_screen.dart apps/mobile/test/features/scan/camera_screen_capture_test.dart apps/mobile/test/features/scan/capture_review_screen_test.dart
git commit -m "feat(b1): wire Accept -> SaveController (save, then home; failure stays on review)"
```

---

### Task 8: BDD — b1_save_document.feature + steps + codegen

**Files:**
- Create: `apps/mobile/integration_test/b1_save_document.feature`
- Generated: `apps/mobile/integration_test/b1_save_document_test.dart` (commit it)
- Create steps: `apps/mobile/test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart`, `apps/mobile/test/step/saving_documents_fails.dart`, `apps/mobile/test/step/i_see_a_saved_document_on_the_home.dart`, `apps/mobile/test/step/i_see_the_save_error.dart`
- Append: `apps/mobile/test/support/fake_library.dart` (temp + failing library deps)

**Interfaces:**
- Consumes: `runCamScannerApp(scanDependencies:, libraryDependencies:)`, `AppDatabase`, `DriftDocumentRepository`, `JpegExifScrubber`, `DocumentFileStore`.

- [ ] **Step 1: Add device-capable library deps helpers.** Append to `apps/mobile/test/support/fake_library.dart`:

```dart
// (add these imports at the top of the file)
// import 'dart:io';
// import 'package:drift/native.dart';
// import 'package:mobile/features/library/document_file_store.dart';
// import 'package:mobile/features/library/drift/app_database.dart';
// import 'package:mobile/features/library/drift/drift_document_repository.dart';
// import 'package:mobile/features/library/jpeg_exif_scrubber.dart';

/// Real DriftDocumentRepository on an in-memory DB + temp file store. Exercises
/// the real save/scrub/list code paths deterministically with no persistent
/// side effects — used by the BDD success scenario on-device.
LibraryDependencies tempLibraryDependencies() => LibraryDependencies(
      createRepository: () async => DriftDocumentRepository(
        db: AppDatabase(NativeDatabase.memory()),
        scrubber: const JpegExifScrubber(),
        fileStore:
            DocumentFileStore(await Directory.systemTemp.createTemp('b1bdd')),
        clock: DateTime.now,
      ),
    );

/// Library deps whose repository always fails — for the save-failure scenario.
LibraryDependencies failingLibraryDependencies() =>
    fakeLibraryDependencies(FakeDocumentRepository(throwOnCreate: true));
```

- [ ] **Step 2: Write the new step definitions.**

`apps/mobile/test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: the app is launched with camera permission granted and empty storage
Future<void> theAppIsLaunchedWithCameraPermissionGrantedAndEmptyStorage(
    WidgetTester tester) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: tempLibraryDependencies(),
  );
  await tester.pumpAndSettle();
}
```

`apps/mobile/test/step/saving_documents_fails.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/main.dart' as app;

import '../support/fake_library.dart';
import '../support/fake_scan.dart';

/// Usage: saving documents fails
Future<void> savingDocumentsFails(WidgetTester tester) async {
  app.runCamScannerApp(
    scanDependencies: grantedScanDependencies(),
    libraryDependencies: failingLibraryDependencies(),
  );
  await tester.pumpAndSettle();
}
```

`apps/mobile/test/step/i_see_a_saved_document_on_the_home.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see a saved document on the home
Future<void> iSeeASavedDocumentOnTheHome(WidgetTester tester) async {
  await tester.pumpAndSettle();
  expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  expect(find.byKey(const Key('documents-list')), findsOneWidget);
  expect(find.textContaining('Scan '), findsWidgets);
}
```

`apps/mobile/test/step/i_see_the_save_error.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the save error
Future<void> iSeeTheSaveError(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text("Couldn't save document. Try again."), findsOneWidget);
}
```

- [ ] **Step 3: Write the feature.** Create `apps/mobile/integration_test/b1_save_document.feature`:

```gherkin
Feature: Save a captured document

  Scenario: Accepting a capture saves it and shows it on the home
    Given the app is launched with camera permission granted and empty storage
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    Then I see a saved document on the home

  Scenario: A failed save keeps me on the review screen
    Given saving documents fails
    When I tap the Scan button
    And I tap the shutter
    And I tap Accept
    Then I see the save error
    And I see the capture review screen
```

- [ ] **Step 4: Generate the BDD test.** Run: `cd apps/mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `Succeeded`; `integration_test/b1_save_document_test.dart` is created. Open it and confirm it imports the four new step files plus the reused `i_tap_the_scan_button`, `i_tap_the_shutter`, `i_tap_accept`, `i_see_the_capture_review_screen`.

- [ ] **Step 5: Run the BDD test on the Android emulator.** Run: `cd apps/mobile && flutter test integration_test/b1_save_document_test.dart -d emulator-5554`
Expected: `All tests passed!`. (If no emulator is booted, launch `Medium_Phone_API_35` first.)

- [ ] **Step 6: Commit** (include the generated test).

```bash
git add apps/mobile/integration_test/b1_save_document.feature apps/mobile/integration_test/b1_save_document_test.dart apps/mobile/test/step/the_app_is_launched_with_camera_permission_granted_and_empty_storage.dart apps/mobile/test/step/saving_documents_fails.dart apps/mobile/test/step/i_see_a_saved_document_on_the_home.dart apps/mobile/test/step/i_see_the_save_error.dart apps/mobile/test/support/fake_library.dart
git commit -m "test(b1): BDD save-document scenarios (success + failure) + steps"
```

---

### Task 9: Verify gate scripts/verify/b1.sh + REAL_DEVICE privacy check + tick criteria

**Files:**
- Create: `apps/mobile/tool/exif_check.dart`
- Create: `scripts/verify/b1.sh`
- Modify: `docs/superpowers/specs/2026-06-27-b1-save-document-design.md` (tick acceptance criteria against evidence)

**Interfaces:**
- Consumes: `lib.sh` helpers (`require_tool`, `assert_cmd`, `assert_coverage_floor`, `assert_file_has`, `verify_integration_android/_ios`, `verify_summary`); the `exif` dev-dependency (for `exif_check.dart`).

- [ ] **Step 1: Write the host EXIF asserter.** Create `apps/mobile/tool/exif_check.dart`:

```dart
import 'dart:io';

import 'package:exif/exif.dart';

/// Reads a JPEG and FAILS (exit 1, prints EXIF_DIRTY) if any identifying tag is
/// present; passes (exit 0, prints `EXIF_CLEAN orientation=<...>`) otherwise.
/// Used by the b1 REAL_DEVICE lane to prove the on-device save is scrubbed.
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('usage: dart run tool/exif_check.dart <file.jpg>');
    exit(2);
  }
  final tags = await readExifFromBytes(File(args[0]).readAsBytesSync());
  const forbidden = [
    'Image Make',
    'Image Model',
    'Image Software',
    'Image DateTime',
    'EXIF DateTimeOriginal',
  ];
  final dirty = <String>[
    ...forbidden.where(tags.containsKey),
    ...tags.keys.where((k) => k.startsWith('GPS')),
  ];
  if (dirty.isNotEmpty) {
    print('EXIF_DIRTY: ${dirty.join(", ")}');
    exit(1);
  }
  print('EXIF_CLEAN orientation=${tags['Image Orientation'] ?? "none"}');
}
```

- [ ] **Step 2: Verify the asserter locally against the fixtures.** Run:
```bash
cd apps/mobile && dart run tool/exif_check.dart test/fixtures/exif_sample.jpg; echo "exit=$?"
```
Expected: `EXIF_DIRTY: Image Make, Image Model, Image Software, Image DateTime` and `exit=1` (the raw fixture is dirty — proves the check detects identifying tags).

- [ ] **Step 3: Write the gate.** Create `scripts/verify/b1.sh`:

```bash
#!/usr/bin/env bash
# Verify B1 (save photo + document record) acceptance criteria.
# Run: bash scripts/verify/b1.sh
# VERIFY_SKIP_DEVICE=1 skips device launches (reported as FAIL, never silent).
# REAL_DEVICE=1 adds the real-camera + on-device privacy (EXIF) lane.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$DIR/lib.sh"
cd "$ROOT"

echo "== B1 verification =="

# ---- Tool preconditions (rule 4) ----
require_tool flutter
require_tool pnpm
require_tool git
require_tool xcrun
if [ -x "$ADB" ]; then pass "tool present: adb"; else fail "required tool MISSING: adb ($ADB)"; fi

# ---- Source presence (static asserts) ----
assert_file_has "DocumentRepository interface exists" \
  "apps/mobile/lib/features/library/document_repository.dart" "abstract interface class DocumentRepository"
assert_file_has "DriftDocumentRepository is transactional" \
  "apps/mobile/lib/features/library/drift/drift_document_repository.dart" "_db.transaction("
assert_file_has "image paths are relative" \
  "apps/mobile/lib/features/library/document_file_store.dart" "documents/\$docId/page_\$position.jpg"
assert_file_has "scrubber is byte-level (no package:image)" \
  "apps/mobile/lib/features/library/jpeg_exif_scrubber.dart" "minimalExifApp1"
assert_file_has "SaveController exists" \
  "apps/mobile/lib/features/library/save_controller.dart" "class SaveController"
assert_file_has "documents list view exists" \
  "apps/mobile/lib/features/library/widgets/documents_list_view.dart" "documents-list"
assert_file_has "EXIF test fixture present" \
  "apps/mobile/test/fixtures/exif_sample.jpg" ""  # presence only (non-empty)

# ---- Generated code is current (Drift + BDD) ----
assert_cmd "codegen is up to date" "Succeeded" \
  bash -c "cd apps/mobile && dart run build_runner build --delete-conflicting-outputs 2>&1"
assert_cmd "no uncommitted generated drift/bdd diff" "" \
  bash -c "git diff --exit-code -- apps/mobile/lib/features/library/drift/app_database.g.dart apps/mobile/integration_test/b1_save_document_test.dart >/dev/null 2>&1 && echo OK || (echo 'GENERATED FILES STALE'; exit 1)"
# NOTE: the marker '' on the line above means 'exit 0 only' — assert_cmd treats
# empty marker as 'no grep, just exit code'. (lib.sh: empty marker matches.)

# ---- Static criteria: unit + widget tests, analyze, coverage ----
assert_cmd "b1 unit + widget tests pass" "All tests passed!" \
  pnpm nx run mobile:test --skip-nx-cache

assert_cmd "analyze clean" "Successfully ran target analyze" \
  pnpm nx run mobile:analyze --skip-nx-cache

assert_coverage_floor 70

# ---- Device criteria: programmatic on-device UI (BDD integration tests) ----
if [ "${VERIFY_SKIP_DEVICE:-0}" = "1" ]; then
  fail "DEVICE CHECKS SKIPPED (VERIFY_SKIP_DEVICE=1) — not a pass; run without the flag to gate"
  verify_summary
fi

verify_integration_android b1_save_document_test.dart
verify_integration_ios b1_save_document_test.dart

# ---- Opt-in real-device lane: real camera -> saved, scrubbed JPEG on disk ----
if [ "${REAL_DEVICE:-0}" = "1" ]; then
  echo "-- REAL_DEVICE lane --"
  rdev="$("$ADB" devices | awk '/device$/{print $1; exit}')"
  if [ -z "$rdev" ]; then
    fail "REAL_DEVICE: no Android device connected"
  else
    apk="apps/mobile/build/app/outputs/flutter-apk/app-debug.apk"
    if ! ( cd apps/mobile && flutter build apk --debug ) >/dev/null 2>&1; then
      fail "REAL_DEVICE: debug APK build failed — skipping the rest of the lane"
    elif ! "$ADB" -s "$rdev" install -r -g "$apk" >/dev/null 2>&1; then
      fail "REAL_DEVICE: adb install -g failed — skipping the rest of the lane"
    else
      pass "REAL_DEVICE: installed with CAMERA pre-granted"
      "$ADB" -s "$rdev" shell pm grant "$APP_ID" android.permission.CAMERA 2>/dev/null
      "$ADB" -s "$rdev" shell svc power stayon true 2>/dev/null
      "$ADB" -s "$rdev" shell input keyevent KEYCODE_WAKEUP 2>/dev/null
      "$ADB" -s "$rdev" shell wm dismiss-keyguard 2>/dev/null
      # Negative control: clear prior saves so the assertion proves THIS run.
      "$ADB" -s "$rdev" shell "run-as $APP_ID find files -iname '*.jpg' -delete" 2>/dev/null
      "$ADB" -s "$rdev" shell am force-stop "$APP_ID" 2>/dev/null
      "$ADB" -s "$rdev" shell monkey -p "$APP_ID" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 7
      size="$("$ADB" -s "$rdev" shell wm size | grep -oE '[0-9]+x[0-9]+' | head -1)"
      w="${size%x*}"; h="${size#*x}"
      # Open Scan (extended FAB ~83% x, ~88.8% y — measured SM-A166B), then
      # shutter (~50% x, ~86% y), then Accept (~83% x bottom-right of review).
      "$ADB" -s "$rdev" shell input tap "$(( w * 83 / 100 ))" "$(( h * 888 / 1000 ))" >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 6
      "$ADB" -s "$rdev" shell input tap "$(( w * 50 / 100 ))" "$(( h * 86 / 100 ))" >/dev/null 2>&1
      "$ADB" -s "$rdev" shell sleep 4   # takePicture + nav to review
      "$ADB" -s "$rdev" shell input tap "$(( w * 75 / 100 ))" "$(( h * 92 / 100 ))" >/dev/null 2>&1  # Accept
      "$ADB" -s "$rdev" shell sleep 5   # scrub + write + insert + nav home
      saved="$("$ADB" -s "$rdev" shell "run-as $APP_ID find files -path '*documents*' -iname '*.jpg' -size +0c" 2>/dev/null | tr -d '\r' | head -1)"
      if [ -n "$saved" ]; then
        pass "REAL_DEVICE: saved a non-empty JPEG under documents/ ($saved)"
        "$ADB" -s "$rdev" exec-out run-as "$APP_ID" cat "$saved" > "$EVIDENCE_DIR/b1-saved.jpg" 2>/dev/null
        # Privacy proof: a concrete EXIF reader (committed exif dev-dep) — no
        # missing-tool silent pass.
        if assert_cmd "REAL_DEVICE: saved JPEG has NO identifying EXIF" "EXIF_CLEAN" \
             bash -c "cd apps/mobile && dart run tool/exif_check.dart '$EVIDENCE_DIR/b1-saved.jpg' 2>&1"; then :; fi
      else
        fail "REAL_DEVICE: no saved JPEG under documents/ [silence=fail]"
      fi
      "$ADB" -s "$rdev" exec-out screencap -p > "$EVIDENCE_DIR/b1-real-home.png" 2>/dev/null
      "$ADB" -s "$rdev" shell svc power stayon false 2>/dev/null
    fi
  fi
  echo "REAL_DEVICE (iOS): MANUAL — confirm a saved document appears upright on a physical iPhone."
fi

verify_summary
```

- [ ] **Step 4: Make it executable and run it (default lane).** Run:
```bash
chmod +x scripts/verify/b1.sh && bash scripts/verify/b1.sh
```
Expected: ends with `VERIFY SUMMARY: N passed, 0 failed` and `GATE: PASS` (exit 0). If a device check fails for infra reasons, fix per `docs/superpowers/VERIFICATION.md` and re-run — do not hand-wave.

- [ ] **Step 5: Tick acceptance criteria.** In `docs/superpowers/specs/2026-06-27-b1-save-document-design.md`, change each `- [ ]` in the **Acceptance criteria** section to `- [x]` ONLY where the named passing test/lane was observed green in Step 4 (and the REAL_DEVICE items only if that lane was run). Leave any unrun item unticked with a one-line note.

- [ ] **Step 6: Commit.**

```bash
git add scripts/verify/b1.sh apps/mobile/tool/exif_check.dart docs/superpowers/specs/2026-06-27-b1-save-document-design.md
git commit -m "test(b1): verify gate (unit/widget/BDD/coverage) + REAL_DEVICE EXIF privacy lane; tick criteria"
```

---

## Self-Review (planner)

**1. Spec coverage:**
- Repository interface + Drift impl → Tasks 1, 4. ✓
- Lossless EXIF strip, Orientation kept, byte-level → Task 2 (fixture validated during planning). ✓
- Relative paths + iOS-safety → Tasks 3 (resolution), 4 (relative persisted). ✓
- Transactional save / crash safety → Task 4. ✓
- SaveController (idle/saving/error, guard, dispose) → Task 5. ✓
- Basic name+date list reading storage, empty state → Task 6. ✓
- Accept → save → home; failure stays on review; saving spinner → Task 7. ✓
- BDD success + failure on Android+iOS → Task 8. ✓
- Verify gate + coverage floor + REAL_DEVICE EXIF privacy → Task 9. ✓
- Deps + codegen committed + schemaVersion → Tasks 1, 8, 9. ✓
- Known gaps (iOS reinstall on sim only; orientation contingency; orphan-file GC) carried in the spec — no task needed. ✓

**2. Placeholder scan:** No TBD/TODO; every code step shows full code; commands have expected output. ✓

**3. Type consistency:** `DocumentRepository.createFromCapture/listDocuments`, `Document{id,name,createdAt,modifiedAt}`, `Page{id,documentId,position,relativeImagePath}`, `SaveStatus{idle,saving,error}`, `SaveController.save`, `CameraScreen({required repository})`, `CaptureReviewScreen({saving})`, `DocumentsListView(documents:)`, `LibraryDependencies.createRepository` are used identically across tasks. The Drift generated row type is also named `Document`/`Page` — the domain models live in `library/document.dart` and the repository maps between them; tests referencing the domain `Document` import that file (not the Drift one). ✓

**Note on Task 6↔7 coupling:** flagged inline — dispatch 6 then 7 and gate them together (or merge), because Home references `CameraScreen(repository:)` which Task 7 introduces.
