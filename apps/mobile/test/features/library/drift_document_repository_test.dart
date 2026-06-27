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
  // ignore: prefer_function_declarations_over_variables
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
    // The repository deletes the temp SOURCE after a successful save (it lives
    // under systemTemp, as the test base does), so reseed it before each call.
    final fixture = File('test/fixtures/exif_sample.jpg').readAsBytesSync();
    void seedSource() => File(capture.path).writeAsBytesSync(fixture);

    var t = DateTime.utc(2026, 6, 27, 10);
    final r = DriftDocumentRepository(
      db: db,
      scrubber: const JpegExifScrubber(),
      fileStore: DocumentFileStore(base),
      clock: () => t,
    );
    seedSource();
    await r.createFromCapture(capture);
    t = DateTime.utc(2026, 6, 27, 12);
    seedSource();
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
