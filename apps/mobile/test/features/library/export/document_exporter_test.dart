import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/export/document_exporter.dart';
import 'package:mobile/features/library/export/export_quality.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/page_image.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/library/pdf/pdf_encryptor.dart';

/// A PdfBuilder that returns fixed bytes (or throws a supplied error).
class _FakePdfBuilder extends PdfBuilder {
  final Object? throwErr;
  const _FakePdfBuilder({this.throwErr});
  @override
  Future<Uint8List> build(
    List<PageImage> pages, {
    bool compress = true,
    ExportQuality quality = ExportQuality.original,
    bool idCardLayout = false,
  }) async {
    if (throwErr != null) throw throwErr!;
    return Uint8List.fromList([0x25, 0x50, 0x44, 0x46]); // %PDF
  }
}

/// Records the password and returns a marker so the file write is observable.
class _RecordingEncryptor implements PdfEncryptor {
  String? password;
  @override
  Future<Uint8List> encrypt(Uint8List pdfBytes, String password) async {
    this.password = password;
    return Uint8List.fromList([...pdfBytes, 0xEE]); // marker
  }
}

void main() {
  late AppDatabase db;
  late Directory base;
  late DocumentFileStore store;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    base = Directory.systemTemp.createTempSync('exporter');
    store = DocumentFileStore(base);
  });
  tearDown(() async {
    await db.close();
    base.deleteSync(recursive: true);
  });

  DocumentExporter exporter({PdfBuilder? pdf, PdfEncryptor? encryptor}) =>
      DocumentExporter(
        db: db,
        fileStore: store,
        pdfBuilder: pdf ?? const _FakePdfBuilder(),
        scrubber: const JpegExifScrubber(),
        encryptor: encryptor,
      );

  Future<int> newDoc(String name, {bool idCard = false}) => db
      .into(db.documents)
      .insert(
        DocumentsCompanion.insert(
          name: name,
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 1, 1),
          isIdCard: Value(idCard),
        ),
      );

  Future<void> addPage(int docId, int pos, {String? ocrText}) => db
      .into(db.pages)
      .insert(
        PagesCompanion.insert(
          documentId: docId,
          position: pos,
          relativeImagePath: store.relativeFor(docId, pos),
          ocrText: Value(ocrText),
        ),
      );

  group('exportPdf', () {
    test('writes a temp PDF named from the sanitized document name', () async {
      final id = await newDoc('My/Doc:2026');
      await addPage(id, 1);
      final file = await exporter().exportPdf(id);
      expect(file.path, endsWith('My_Doc_2026.pdf'));
      expect(await file.readAsBytes(), [0x25, 0x50, 0x44, 0x46]);
    });

    test('throws "no pages" for an empty document', () async {
      final id = await newDoc('Empty');
      expect(
        () => exporter().exportPdf(id),
        throwsA(
          isA<DocumentExportException>().having(
            (e) => e.message,
            'message',
            'export failed: no pages',
          ),
        ),
      );
    });

    test(
      'rethrows a DocumentExportException from the builder unchanged',
      () async {
        final id = await newDoc('X');
        await addPage(id, 1);
        final ex = exporter(
          pdf: const _FakePdfBuilder(
            throwErr: DocumentExportException('inner boom'),
          ),
        );
        expect(
          () => ex.exportPdf(id),
          throwsA(
            isA<DocumentExportException>().having(
              (e) => e.message,
              'message',
              'inner boom',
            ),
          ),
        );
      },
    );
  });

  group('exportProtectedPdf', () {
    test('encrypts the built bytes with the given password', () async {
      final id = await newDoc('Doc');
      await addPage(id, 1);
      final enc = _RecordingEncryptor();
      final file = await exporter(encryptor: enc).exportProtectedPdf(id, 'pw');
      expect(enc.password, 'pw');
      expect((await file.readAsBytes()).last, 0xEE); // encryptor ran
    });
  });

  group('exportCombinedPdf', () {
    test('throws when no document ids are given', () async {
      expect(
        () => exporter().exportCombinedPdf(const []),
        throwsA(isA<DocumentExportException>()),
      );
    });

    test('throws "no pages" when every document is empty', () async {
      final id = await newDoc('Empty');
      expect(
        () => exporter().exportCombinedPdf([id]),
        throwsA(
          isA<DocumentExportException>().having(
            (e) => e.message,
            'message',
            'combined export failed: no pages',
          ),
        ),
      );
    });
  });

  group('exportRecognizedText', () {
    test('writes the cached OCR text to a temp .txt', () async {
      final id = await newDoc('Doc');
      await addPage(id, 1, ocrText: 'hello world');
      final file = await exporter().exportRecognizedText(id, 1);
      expect(file.path, endsWith('Doc_page_1.txt'));
      expect(await file.readAsString(), 'hello world');
    });

    test('throws when the page has no recognized text', () async {
      final id = await newDoc('Doc');
      await addPage(id, 1);
      expect(
        () => exporter().exportRecognizedText(id, 1),
        throwsA(isA<DocumentExportException>()),
      );
    });
  });
}
