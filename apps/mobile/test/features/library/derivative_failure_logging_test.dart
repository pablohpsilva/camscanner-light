import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/core/logging/app_logger.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/drift/app_database.dart';
import 'package:mobile/features/library/drift/drift_document_repository.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/jpeg_exif_scrubber.dart';
import 'package:mobile/features/library/page_processor.dart';
import 'package:mobile/features/library/pdf/pdf_builder.dart';
import 'package:mobile/features/scan/captured_image.dart';

import '../../support/fake_library.dart';

/// P10 T10.7 (SAFE-03): a derivative (flat) regen failure must NOT fail the
/// save — but it must no longer be swallowed silently; it is reported via
/// [AppLogger].
class _ThrowingProcessor implements PageProcessor {
  @override
  Future<Uint8List?> process(
    Uint8List b,
    CropCorners c,
    EnhancerMode m,
  ) async => throw Exception('processor boom');
}

void main() {
  late Directory base;
  late AppDatabase db;
  late CapturedImage capture;

  setUp(() {
    base = Directory.systemTemp.createTempSync('derivlog');
    db = AppDatabase(NativeDatabase.memory());
    final src = File('${base.path}/cap.jpg')
      ..writeAsBytesSync(
        File('test/fixtures/exif_sample.jpg').readAsBytesSync(),
      );
    capture = CapturedImage(src.path);
  });
  tearDown(() async {
    await db.close();
    if (base.existsSync()) base.deleteSync(recursive: true);
  });

  test(
    'createFromCapture: flat regen failure saves base only AND logs it',
    () async {
      final logger = SilentAppLogger();
      final repo = DriftDocumentRepository(
        db: db,
        scrubber: const JpegExifScrubber(),
        fileStore: DocumentFileStore(base),
        clock: () => DateTime.utc(2026, 1, 1),
        pdfBuilder: const PdfBuilder(),
        warper: FakeImageWarper(),
        pageProcessor: _ThrowingProcessor(),
        logger: logger,
      );

      final doc = await repo.createFromCapture(
        capture,
        enhancer: const GrayscaleEnhancer(),
      );

      final pages = await repo.getDocumentPages(doc.id);
      expect(pages, hasLength(1), reason: 'the save still succeeds');
      expect(pages.single.flatImagePath, isNull, reason: 'saved base only');
      expect(
        logger.records.any((r) => r.context?.contains('flat regen') ?? false),
        isTrue,
        reason: 'the derivative failure must be reported, not swallowed',
      );
    },
  );
}
