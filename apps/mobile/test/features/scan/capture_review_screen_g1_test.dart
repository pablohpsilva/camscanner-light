import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

/// Helper: pumps CaptureReviewScreen with a non-loadable image path,
/// instant size resolution, and the given onAccept callback.
Future<void> _pump(
  WidgetTester tester, {
  required void Function(CropCorners, ImageEnhancer) onAccept,
  bool saving = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/g1.jpg'),
      onRetake: () {},
      onAccept: onAccept,
      saving: saving,
      decodeImageSize: (_) async => const Size(100, 100),
      readBytes: (_) async => Uint8List(0),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('grayscale toggle button is present in the AppBar',
      (tester) async {
    await _pump(tester, onAccept: (_, _) {});
    expect(find.byKey(const Key('grayscale-toggle')), findsOneWidget);
  });

  testWidgets('tapping toggle changes its tooltip', (tester) async {
    await _pump(tester, onAccept: (_, _) {});

    final before = tester.widget<IconButton>(
        find.byKey(const Key('grayscale-toggle')));
    expect(before.tooltip, equals('Grayscale off'));

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();

    final after = tester.widget<IconButton>(
        find.byKey(const Key('grayscale-toggle')));
    expect(after.tooltip, equals('Grayscale on'));
  });

  testWidgets('Accept with toggle on calls onAccept with GrayscaleEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<GrayscaleEnhancer>());
  });

  testWidgets('Accept with toggle off calls onAccept with NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    // No toggle tap — default is NoneEnhancer.
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>());
  });
}
