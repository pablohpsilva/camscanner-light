import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/document_file_store.dart';
import 'package:mobile/features/library/document_repository.dart'
    show DocumentSaveException;
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/jpeg_rotator.dart';
import 'package:mobile/features/library/page_derivative_pipeline.dart';
import 'package:mobile/features/library/page_processor.dart';

/// A rotator that returns fixed bytes and records the quarter-turns it saw.
class _FakeRotator implements JpegRotator {
  final Uint8List? out;
  int? lastQuarterTurns;
  _FakeRotator(this.out);
  @override
  Future<Uint8List?> rotate(Uint8List bytes, int quarterTurns) async {
    lastQuarterTurns = quarterTurns;
    return out;
  }
}

/// A processor returning a fixed result (or null to trigger the fallbacks).
class _FakeProcessor implements PageProcessor {
  final Uint8List? out;
  int calls = 0;
  _FakeProcessor(this.out);
  @override
  Future<Uint8List?> process(
    Uint8List bytes,
    CropCorners corners,
    EnhancerMode mode,
  ) async {
    calls++;
    return out;
  }
}

void main() {
  late Directory base;
  late DocumentFileStore store;
  final baseBytes = Uint8List.fromList([1, 1, 1]);
  final rotated = Uint8List.fromList([2, 2, 2]);
  final processed = Uint8List.fromList([3, 3, 3]);

  const imageRel = 'documents/7/page_1.jpg';
  final flatRel = 'documents/7/page_1_flat.jpg';

  // A non-full-frame crop (drives the warp+enhance branch).
  CropCorners crop() => const CropCorners(
    topLeft: Offset(0.1, 0.1),
    topRight: Offset(0.9, 0.1),
    bottomRight: Offset(0.9, 0.9),
    bottomLeft: Offset(0.1, 0.9),
  );

  setUp(() async {
    base = Directory.systemTemp.createTempSync('pdp');
    store = DocumentFileStore(base);
    await store.writeRelative(imageRel, baseBytes); // pristine base on disk
  });
  tearDown(() => base.deleteSync(recursive: true));

  PageDerivativePipeline pipeline({
    JpegRotator? rotator,
    PageProcessor? processor,
  }) => PageDerivativePipeline(
    fileStore: store,
    processor: processor ?? _FakeProcessor(null),
    rotator: rotator ?? _FakeRotator(rotated),
    rotateTimeout: const Duration(seconds: 5),
  );

  Uint8List? flatOnDisk() {
    final f = File('${base.path}/$flatRel');
    return f.existsSync() ? f.readAsBytesSync() : null;
  }

  test('fast path (no rotate, full-frame, mode none) returns null and deletes '
      'an existing flat', () async {
    await store.writeRelative(flatRel, processed); // a stale flat to remove
    final proc = _FakeProcessor(processed);
    final result = await pipeline(processor: proc).writeFlat(
      relativeImagePath: imageRel,
      quarterTurns: 0,
      corners: CropCorners.fullFrame,
      mode: EnhancerMode.none,
      existingFlatRel: flatRel,
    );
    expect(result, isNull);
    expect(flatOnDisk(), isNull, reason: 'stale flat must be deleted');
    expect(proc.calls, 0, reason: 'fast path does no image work');
  });

  test(
    'rotate-only (mode none, quarterTurns 1) writes the rotated bytes',
    () async {
      final rot = _FakeRotator(rotated);
      final proc = _FakeProcessor(null);
      final result = await pipeline(rotator: rot, processor: proc).writeFlat(
        relativeImagePath: imageRel,
        quarterTurns: 1,
        corners: CropCorners.fullFrame,
        mode: EnhancerMode.none,
        existingFlatRel: null,
      );
      expect(result, flatRel);
      expect(flatOnDisk(), rotated);
      expect(
        rot.lastQuarterTurns,
        1,
        reason: 'rotator called with right turns',
      );
      expect(proc.calls, 0, reason: 'mode none skips the processor');
    },
  );

  test('full-frame enhance falls back to the input when the processor returns '
      'null', () async {
    // quarterTurns 0 → input is the base; processor null → write base verbatim.
    final result = await pipeline(processor: _FakeProcessor(null)).writeFlat(
      relativeImagePath: imageRel,
      quarterTurns: 0,
      corners: CropCorners.fullFrame,
      mode: EnhancerMode.grayscale,
      existingFlatRel: null,
    );
    expect(result, flatRel);
    expect(flatOnDisk(), baseBytes);
  });

  test('full-frame enhance writes the processed bytes on success', () async {
    final result = await pipeline(processor: _FakeProcessor(processed))
        .writeFlat(
          relativeImagePath: imageRel,
          quarterTurns: 0,
          corners: CropCorners.fullFrame,
          mode: EnhancerMode.color,
          existingFlatRel: null,
        );
    expect(result, flatRel);
    expect(flatOnDisk(), processed);
  });

  test('cropped path falls back to the rotated image when the processor '
      'returns null', () async {
    final corners = crop();
    final result =
        await pipeline(
          rotator: _FakeRotator(rotated),
          processor: _FakeProcessor(null),
        ).writeFlat(
          relativeImagePath: imageRel,
          quarterTurns: 1,
          corners: corners,
          mode: EnhancerMode.none,
          existingFlatRel: null,
        );
    expect(result, flatRel);
    expect(flatOnDisk(), rotated, reason: 'falls back to rotated bytes');
  });

  test('final null (cropped, no rotate, processor null) returns null and '
      'deletes the existing flat', () async {
    await store.writeRelative(flatRel, processed);
    final corners = crop();
    final result = await pipeline(processor: _FakeProcessor(null)).writeFlat(
      relativeImagePath: imageRel,
      quarterTurns: 0,
      corners: corners,
      mode: EnhancerMode.none,
      existingFlatRel: flatRel,
    );
    expect(result, isNull);
    expect(flatOnDisk(), isNull);
  });

  test('an undecodable base (rotator returns null) throws '
      'DocumentSaveException', () async {
    await expectLater(
      pipeline(rotator: _FakeRotator(null)).writeFlat(
        relativeImagePath: imageRel,
        quarterTurns: 1,
        corners: CropCorners.fullFrame,
        mode: EnhancerMode.none,
        existingFlatRel: null,
      ),
      throwsA(isA<DocumentSaveException>()),
    );
  });
}
