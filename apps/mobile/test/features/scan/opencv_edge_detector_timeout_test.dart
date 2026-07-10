import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/opencv_edge_detector.dart';

/// These tests exercise the timeout guard around the native pipeline WITHOUT
/// the real OpenCV library, by injecting a pipeline runner via
/// [OpenCvEdgeDetector.withRunner]. They run green on the host (unlike the
/// real-OpenCV tests, which need libdartcv and can wedge the native isolate).
void main() {
  group('OpenCvEdgeDetector timeout guard', () {
    test(
      'returns null (never hangs) when the pipeline exceeds the timeout',
      () async {
        // A runner that never completes — simulates a wedged native pipeline.
        final detector = OpenCvEdgeDetector.withRunner(
          (_) => Completer<List<double>?>().future,
          timeout: const Duration(milliseconds: 50),
        );

        final result = await detector.detect(Uint8List(0));

        expect(result, isNull);
      },
    );

    test('maps a completed pipeline result to a DetectionResult', () async {
      final detector = OpenCvEdgeDetector.withRunner(
        (_) async => <double>[0.1, 0.1, 0.9, 0.1, 0.9, 0.9, 0.1, 0.9, 0.8],
        timeout: const Duration(seconds: 5),
      );

      final result = await detector.detect(Uint8List(0));

      expect(result, isNotNull);
      expect(result!.confidence, 0.8);
      expect(result.corners.topLeft, const Offset(0.1, 0.1));
      expect(result.corners.bottomRight, const Offset(0.9, 0.9));
    });

    test('returns null when the pipeline resolves with null', () async {
      final detector = OpenCvEdgeDetector.withRunner(
        (_) async => null,
        timeout: const Duration(seconds: 5),
      );

      final result = await detector.detect(Uint8List(0));

      expect(result, isNull);
    });
  });
}
