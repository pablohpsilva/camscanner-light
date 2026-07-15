import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/page_processor.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

/// A [DocumentFileStore] that can be ARMED to throw on the Nth write once
/// armed, and records every relative path it actually wrote. Lets a test force
/// a mid-copy failure and then assert which files leaked / were cleaned up.
class _ArmableFailFileStore extends DocumentFileStore {
  _ArmableFailFileStore(super.baseDir);
  bool armed = false;
  int failOnArmedWrite = 1;
  int _armedWrites = 0;
  final List<String> written = <String>[];

  @override
  Future<void> writeRelative(String relativePath, List<int> bytes) async {
    if (armed) {
      _armedWrites++;
      if (_armedWrites == failOnArmedWrite) {
        throw const FileSystemException('injected write failure');
      }
    }
    await super.writeRelative(relativePath, bytes);
    written.add(relativePath);
  }
}

/// A repository whose [deleteDocument] crashes for one id — models a process
/// death AFTER `mergeInto`'s inserts commit but BEFORE the source rows are
/// deleted (the buggy "pages live in both documents" window). On code that has
/// folded the source deletion INTO the merge transaction this override never
/// fires, so the merge completes cleanly.
class _MergeSourceDeleteCrashRepo extends DriftDocumentRepository {
  _MergeSourceDeleteCrashRepo(
    this.crashOnDeleteId, {
    required super.db,
    required super.scrubber,
    required super.fileStore,
    required super.clock,
    required super.pdfBuilder,
    required super.warper,
  });
  final int crashOnDeleteId;

  @override
  Future<void> deleteDocument(int documentId) {
    if (documentId == crashOnDeleteId) {
      throw const DocumentSaveException('injected: crash before source delete');
    }
    return super.deleteDocument(documentId);
  }
}

/// A [PageProcessor] that blocks inside [process] until [gate] completes and
/// signals [reached] when entered — lets a test observe DB state while the
/// (possibly transaction-bound) image work is in flight.
class _GatedProcessor implements PageProcessor {
  _GatedProcessor({
    required this.gate,
    required this.reached,
    required this.flat,
  });
  final Completer<void> gate;
  final Completer<void> reached;
  final Uint8List flat;

  @override
  Future<Uint8List?> process(Uint8List b, CropCorners c, EnhancerMode m) async {
    if (!reached.isCompleted) reached.complete();
    await gate.future;
    return flat;
  }
}

void main() {
  late Directory base;
  late AppDatabase db;
  late Uint8List fixture;
  var capN = 0;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('p03atomic');
    db = AppDatabase(NativeDatabase.memory());
    fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
  });
  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  DriftDocumentRepository repo({
    DocumentFileStore? fileStore,
    PageProcessor? pageProcessor,
    AppLogger? logger,
  }) => DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: fileStore ?? DocumentFileStore(base),
    clock: clock,
    pdfBuilder: const PdfBuilder(),
    warper: FakeImageWarper(),
    pageProcessor: pageProcessor,
    logger: logger ?? const PrintAppLogger(),
  );

  /// Seed a document with [pages] real on-disk page files + rows, directly at
  /// the DB/file level (bypassing the capture pipeline).
  Future<int> seedDoc(String name, int pages) async {
    final id = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: name,
            createdAt: DateTime.utc(2026, 1, 1),
            modifiedAt: DateTime.utc(2026, 1, 1),
          ),
        );
    for (var pos = 1; pos <= pages; pos++) {
      final rel = 'documents/$id/page_$pos.jpg';
      final f = File('${base.path}/$rel');
      await f.create(recursive: true);
      f.writeAsBytesSync(fixture);
      await db
          .into(db.pages)
          .insert(
            PagesCompanion.insert(
              documentId: id,
              position: pos,
              relativeImagePath: rel,
            ),
          );
    }
    return id;
  }

  CapturedImage freshCapture() {
    final f = File('${base.path}/cap_${capN++}.jpg')
      ..writeAsBytesSync(fixture);
    return CapturedImage(f.path);
  }

  group('SAFE-01 merge/split atomicity', () {
    test('mergeInto never leaves a page in BOTH documents when the source '
        'deletion crashes mid-operation', () async {
      final targetId = await seedDoc('target', 1);
      final sourceId = await seedDoc('source', 2);
      final r = _MergeSourceDeleteCrashRepo(
        sourceId,
        db: db,
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: clock,
        pdfBuilder: const PdfBuilder(),
        warper: FakeImageWarper(),
      );

      try {
        await r.mergeInto(targetId, sourceId);
      } catch (_) {
        /* the injected crash may surface — the invariant is about STATE */
      }

      final ids = (await r.listDocumentSummaries())
          .map((s) => s.document.id)
          .toSet();
      final targetPages = await r.getDocumentPages(targetId);
      if (ids.contains(sourceId)) {
        // Rolled back: source still exists, so target must be UNCHANGED —
        // the source's pages must NOT also have been copied in.
        expect(
          targetPages,
          hasLength(1),
          reason: 'source survived, so target must not hold the merged pages',
        );
      } else {
        // Committed: source gone, target holds every page.
        expect(
          targetPages,
          hasLength(3),
          reason: 'source removed, so target must hold all merged pages',
        );
      }
    });

    test('splitAfter never duplicates a moved page across documents when a '
        'page copy fails mid-operation', () async {
      final store = _ArmableFailFileStore(base);
      final r = repo(fileStore: store);
      final sourceId = await seedDoc('splitsrc', 3);

      store
        ..armed = true
        ..failOnArmedWrite = 2; // fail on the 2nd moved-page copy

      try {
        await r.splitAfter(sourceId, 1); // moves pages 2 & 3 to a new doc
      } catch (_) {
        /* invariant is about STATE, not the thrown error */
      }
      store.armed = false;

      final summaries = await r.listDocumentSummaries();
      final sourcePages = await r.getDocumentPages(sourceId);
      if (summaries.length == 1) {
        // Rolled back: no new document, source keeps ALL its pages.
        expect(
          sourcePages,
          hasLength(3),
          reason: 'no new doc created, so the source must be intact',
        );
      } else {
        // Committed: the split happened, source keeps only page 1.
        expect(
          sourcePages,
          hasLength(1),
          reason: 'split committed, so moved pages must be gone from source',
        );
      }
    });
  });

  group('SAFE-02 no write-lock held across image work', () {
    test(
      'createFromCapture does not hold the write transaction across image work',
      () async {
        final gate = Completer<void>();
        final reached = Completer<void>();
        final r = repo(
          pageProcessor: _GatedProcessor(
            gate: gate,
            reached: reached,
            flat: fixture,
          ),
        );

        final creating = r.createFromCapture(
          freshCapture(),
          enhancer: const GrayscaleEnhancer(),
        );
        await reached.future; // image work is now in flight

        var readDone = false;
        // A concurrent read must NOT be queued behind an open write txn.
        unawaited(r.listDocumentSummaries().then((_) => readDone = true));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final readCompletedDuringImageWork = readDone;

        gate.complete();
        await creating;

        expect(
          readCompletedDuringImageWork,
          isTrue,
          reason: 'the write transaction must not span the image work',
        );
      },
    );

    test(
      'addPageToDocument does not hold the write transaction across image work',
      () async {
        final gate = Completer<void>();
        final reached = Completer<void>();
        final r = repo(
          pageProcessor: _GatedProcessor(
            gate: gate,
            reached: reached,
            flat: fixture,
          ),
        );
        // Seed a doc with NO enhancer → fast path, the gate is not armed here.
        final doc = await r.createFromCapture(freshCapture());

        final adding = r.addPageToDocument(
          doc.id,
          freshCapture(),
          enhancer: const GrayscaleEnhancer(),
        );
        await reached.future;

        var readDone = false;
        unawaited(r.listDocumentSummaries().then((_) => readDone = true));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        final readCompletedDuringImageWork = readDone;

        gate.complete();
        await adding;

        expect(
          readCompletedDuringImageWork,
          isTrue,
          reason: 'the write transaction must not span the image work',
        );
      },
    );
  });

  group('SAFE-01 failure cleanup', () {
    test(
      'a mid-copy failure deletes the files already written and logs it',
      () async {
        final store = _ArmableFailFileStore(base);
        final logger = SilentAppLogger();
        final r = repo(fileStore: store, logger: logger);
        final sourceId = await seedDoc('cleanup', 3);

        store
          ..armed = true
          ..failOnArmedWrite = 2;

        try {
          await r.splitAfter(sourceId, 1);
        } catch (_) {
          /* expected */
        }
        store.armed = false;

        // Every file the split managed to copy before failing must be cleaned
        // up (none of them belong to the source doc — those were seeded direct).
        expect(store.written, isNotEmpty, reason: 'at least one copy happened');
        for (final rel in store.written) {
          expect(
            File('${base.path}/$rel').existsSync(),
            isFalse,
            reason:
                'copied file $rel must be cleaned up after the failed split',
          );
        }
        expect(
          logger.records,
          isNotEmpty,
          reason: 'the cleanup must be reported via AppLogger',
        );
      },
    );
  });
}
