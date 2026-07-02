import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/edge_detector.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/widgets/crop_overlay.dart';

/// A detector that returns a fixed confidence so we can drive the tint tiers.
class _FakeDetector implements EdgeDetector {
  final double confidence;
  const _FakeDetector(this.confidence);
  @override
  Future<DetectionResult?> detect(Uint8List bytes) async => DetectionResult(
        corners: CropCorners.fullFrame,
        confidence: confidence,
      );
}

Future<Color> _highlightFor(WidgetTester tester, double confidence) async {
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/h.jpg'),
      onRetake: () {},
      onAccept: (_, _) {},
      decodeImageSize: (_) async => const Size(100, 100),
      readBytes: (_) async => Uint8List.fromList(List.filled(64, 1)),
      edgeDetector: _FakeDetector(confidence),
    ),
  ));
  // Use multiple pumps instead of pumpAndSettle to avoid hanging on perpetual animations
  for (int i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final overlay = tester.widget<CropOverlay>(find.byType(CropOverlay));
  return overlay.highlightColor;
}

void main() {
  testWidgets('confidence >= 0.6 tints green', (tester) async {
    expect(await _highlightFor(tester, 0.8), Colors.green);
  });

  testWidgets('0.3 <= confidence < 0.6 tints amber (please check)',
      (tester) async {
    expect(await _highlightFor(tester, 0.45), Colors.amber);
  });

  testWidgets('confidence < 0.3 tints blue (fallback)', (tester) async {
    expect(await _highlightFor(tester, 0.1), Colors.blue);
  });
}
