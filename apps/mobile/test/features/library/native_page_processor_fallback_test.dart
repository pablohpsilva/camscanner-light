import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/library/native_page_processor.dart';

/// P08 Task 5: the native→Dart fallback + timeout handoff is now host-testable
/// via the `withRunner` seam (mirroring OpenCvEdgeDetector) — no libdartcv
/// needed. These prove `process` returns null (so a fallback can take over) on
/// a wedged/failing runner, and that the cheap short-circuit guards never even
/// invoke the runner.
void main() {
  final bytes = Uint8List.fromList(const [1, 2, 3, 4]);
  // A straight crop (not fullFrame) so the bent-crop guard does not fire.
  final straightCrop = CropCorners.fullFrame.copyWith(
    topLeft: const Offset(0.05, 0.05),
    topRight: const Offset(0.95, 0.05),
    bottomRight: const Offset(0.95, 0.95),
    bottomLeft: const Offset(0.05, 0.95),
  );

  test(
    'a never-completing runner → process returns null within the timeout',
    () async {
      final processor = NativePageProcessor.withRunner(
        (_, _, _) => Completer<Uint8List?>().future, // never completes
        timeout: const Duration(milliseconds: 50),
      );
      final result = await processor.process(
        bytes,
        CropCorners.fullFrame,
        EnhancerMode.auto,
      );
      expect(result, isNull);
    },
  );

  test('a throwing runner → process returns null (fallback)', () async {
    final processor = NativePageProcessor.withRunner(
      (_, _, _) async => throw StateError('native boom'),
    );
    final result = await processor.process(
      bytes,
      CropCorners.fullFrame,
      EnhancerMode.auto,
    );
    expect(result, isNull);
  });

  test('a runner returning null → process returns null', () async {
    final processor = NativePageProcessor.withRunner((_, _, _) async => null);
    final result = await processor.process(
      bytes,
      straightCrop,
      EnhancerMode.auto,
    );
    expect(result, isNull);
  });

  test('a runner returning bytes → process passes them through', () async {
    final out = Uint8List.fromList(const [9, 9, 9]);
    final processor = NativePageProcessor.withRunner((_, _, _) async => out);
    final result = await processor.process(
      bytes,
      straightCrop,
      EnhancerMode.color,
    );
    expect(result, same(out));
  });

  test(
    'none + fullFrame short-circuits to null WITHOUT invoking the runner',
    () async {
      var called = false;
      final processor = NativePageProcessor.withRunner((_, _, _) async {
        called = true;
        return null;
      });
      final result = await processor.process(
        bytes,
        CropCorners.fullFrame,
        EnhancerMode.none,
      );
      expect(result, isNull);
      expect(called, isFalse);
    },
  );

  test(
    'a bent crop short-circuits to null WITHOUT invoking the runner',
    () async {
      var called = false;
      final bent = CropCorners.fullFrame.copyWith(
        topMidDev: const Offset(0.1, 0.1), // non-zero deviation ⇒ not straight
      );
      final processor = NativePageProcessor.withRunner((_, _, _) async {
        called = true;
        return null;
      });
      final result = await processor.process(bytes, bent, EnhancerMode.auto);
      expect(result, isNull);
      expect(called, isFalse);
    },
  );

  test(
    'the runner receives the exact bytes/corners/mode passed to process',
    () async {
      Uint8List? seenBytes;
      CropCorners? seenCorners;
      EnhancerMode? seenMode;
      final processor = NativePageProcessor.withRunner((b, c, m) async {
        seenBytes = b;
        seenCorners = c;
        seenMode = m;
        return null;
      });
      await processor.process(bytes, straightCrop, EnhancerMode.grayscale);
      expect(seenBytes, same(bytes));
      expect(seenCorners, straightCrop);
      expect(seenMode, EnhancerMode.grayscale);
    },
  );
}
