import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/ocr/ocr_engine.dart';
import 'package:mobile/features/library/ocr/ocr_result.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';

import '../../support/fake_library.dart';

/// Captures the bytes it was asked to recognize (to prove which file was read).
class _RecordingOcrEngine implements OcrEngine {
  Uint8List? received;
  @override
  Future<OcrResult> recognize(Uint8List imageBytes) async {
    received = imageBytes;
    return const OcrResult(text: 'REC', words: []);
  }
}

void main() {
  late Directory base;
  late AppDatabase db;
  // ignore: prefer_function_declarations_over_variables
  final clock = () => DateTime.utc(2026, 6, 27, 20, 26, 42);

  setUp(() {
    base = Directory.systemTemp.createTempSync('o1ocr');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  DriftDocumentRepository repo({OcrEngine? ocr}) => DriftDocumentRepository(
    db: db,
    scrubber: const JpegExifScrubber(),
    fileStore: DocumentFileStore(base),
    clock: clock,
    pdfBuilder: const PdfBuilder(),
    warper: FakeImageWarper(),
    ocrEngine: ocr ?? const NoOpOcrEngine(),
  );

  Uint8List fixture(String name) =>
      File('test/fixtures/$name').readAsBytesSync();

  // Seed a doc + one page, writing the image file(s) directly.
  Future<int> seedDoc({required String image, String? flat}) async {
    final now = clock();
    final store = DocumentFileStore(base);
    final docId = await db
        .into(db.documents)
        .insert(
          DocumentsCompanion.insert(
            name: 'Doc',
            createdAt: now,
            modifiedAt: now,
          ),
        );
    final rel = 'documents/$docId/page_1.jpg';
    await store.writeRelative(rel, fixture(image));
    String? flatRel;
    if (flat != null) {
      flatRel = 'documents/$docId/page_1_flat.jpg';
      await store.writeRelative(flatRel, fixture(flat));
    }
    await db
        .into(db.pages)
        .insert(
          PagesCompanion.insert(
            documentId: docId,
            position: 1,
            relativeImagePath: rel,
            flatRelativePath: Value(flatRel),
          ),
        );
    return docId;
  }

  test('runOcr caches recognized text + boxes (FakeOcrEngine)', () async {
    final docId = await seedDoc(image: 'exif_sample.jpg');
    await repo(ocr: const FakeOcrEngine()).runOcr(docId, 1);

    final row = (await db.select(db.pages).get()).single;
    expect(row.ocrText, 'HELLO WORLD');
    expect(OcrResult.decodeBoxes(row.ocrBoxes).length, 2);
  });

  test(
    'runOcr with NoOpOcrEngine caches empty text (ran, found nothing)',
    () async {
      final docId = await seedDoc(image: 'exif_sample.jpg');
      await repo().runOcr(docId, 1);

      final row = (await db.select(db.pages).get()).single;
      expect(row.ocrText, ''); // empty, NOT null
      expect(row.ocrBoxes, '[]');
    },
  );

  test('runOcr on a missing page throws DocumentSaveException', () async {
    final docId = await seedDoc(image: 'exif_sample.jpg');
    await expectLater(
      repo().runOcr(docId, 99),
      throwsA(isA<DocumentSaveException>()),
    );
  });

  test('getDocumentPages exposes ocrText after runOcr', () async {
    final docId = await seedDoc(image: 'exif_sample.jpg');
    await repo(ocr: const FakeOcrEngine()).runOcr(docId, 1);
    final pages = await repo().getDocumentPages(docId);
    expect(pages.single.ocrText, 'HELLO WORLD');
  });

  test('runOcr reads the FLAT image when present', () async {
    final docId = await seedDoc(
      image: 'exif_sample.jpg',
      flat: 'landscape_exif6.jpg',
    );
    final rec = _RecordingOcrEngine();
    await repo(ocr: rec).runOcr(docId, 1);
    expect(
      rec.received,
      fixture('landscape_exif6.jpg'),
      reason: 'runOcr recognizes the flat derivative, not the original',
    );
  });
}
