import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';
import 'package:mobile/features/scan/edge_detector.dart';

import '../../support/localized_app.dart';

/// Resolves immediately so no detection timer outlives the widget tree.
class _InstantDetector implements EdgeDetector {
  const _InstantDetector();
  @override
  Future<DetectionResult?> detect(Uint8List bytes) async =>
      DetectionResult(corners: CropCorners.fullFrame, confidence: 0.9);
}

/// The capture-review action row (Retake / Reset / Accept) must not overflow.
///
/// Found on a physical iPhone (iOS 26.6.1), where it overflowed by 1.5px and
/// took `e1_crop` and `e2_flatten` down with it — a RenderFlex overflow is an
/// error in tests, so the device runs failed before reaching their assertions.
///
/// 430x932 is the iPhone Pro Max logical size: 430 - 16 - 16 of padding leaves
/// the 398px the failing device reported. The row is widest with all three
/// buttons, so `enableCrop: true` is the case that must fit.
void main() {
  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      localizedTestApp(
        home: CaptureReviewScreen(
          image: const CapturedImage('/nonexistent/a.jpg'),
          onRetake: () {},
          onAccept: (_, _) {},
          enableCrop: true,
          decodeImageSize: (_) async => const Size(100, 100),
          readBytes: (_) async => Uint8List.fromList(List.filled(64, 1)),
          edgeDetector: const _InstantDetector(),
        ),
      ),
    );
    // Perpetual animations make pumpAndSettle hang here; pump a bounded number.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // The screen arms a detection timeout timer; fire it, or flutter_test's
    // pending-timer invariant fails the test before our assertions are read
    // (same trick as capture_review_highlight_test).
    await tester.pump(const Duration(seconds: 7));
  }

  testWidgets('the action row fits an iPhone Pro Max width', (tester) async {
    await pumpAt(tester, const Size(430, 932));

    expect(find.byKey(const Key('review-retake')), findsOneWidget);
    expect(find.byKey(const Key('crop-reset')), findsOneWidget);
    expect(find.byKey(const Key('review-accept')), findsOneWidget);
    // tester.takeException() surfaces the RenderFlex overflow that layout threw.
    expect(tester.takeException(), isNull);
  });

  testWidgets('the action row fits a narrow phone width', (tester) async {
    // A 360pt Android phone is narrower still — if the row only just fits the
    // iPhone, it must be flexible enough for this too.
    await pumpAt(tester, const Size(360, 800));
    expect(tester.takeException(), isNull);
  });
}
