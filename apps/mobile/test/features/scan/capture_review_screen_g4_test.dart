import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
import 'package:mobile/features/library/bw_enhancer.dart';
import 'package:mobile/features/library/color_enhancer.dart';
import 'package:mobile/features/library/crop_corners.dart';
import 'package:mobile/features/library/grayscale_enhancer.dart';
import 'package:mobile/features/library/image_enhancer.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/captured_image.dart';

Future<void> _pump(
  WidgetTester tester, {
  required void Function(CropCorners, ImageEnhancer) onAccept,
  bool saving = false,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: CaptureReviewScreen(
      image: const CapturedImage('/nonexistent/g4.jpg'),
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
  testWidgets('filter-picker-strip is present in the review screen',
      (tester) async {
    await _pump(tester, onAccept: (_, e) {});
    expect(find.byKey(const Key('filter-picker-strip')), findsOneWidget);
  });

  testWidgets('old AppBar toggle keys are absent', (tester) async {
    await _pump(tester, onAccept: (_, e) {});
    expect(find.byKey(const Key('grayscale-toggle')), findsNothing);
    expect(find.byKey(const Key('bw-toggle')), findsNothing);
    expect(find.byKey(const Key('auto-toggle')), findsNothing);
    expect(find.byKey(const Key('color-toggle')), findsNothing);
  });

  testWidgets(
      'default mode is Auto — Accept without tile tap passes AutoEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>(),
        reason: 'Auto is the default — no tile tap needed');
  });

  testWidgets('tapping Original tile then Accept passes NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-original')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>());
  });

  testWidgets('tapping Grayscale tile then Accept passes GrayscaleEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<GrayscaleEnhancer>());
  });

  testWidgets('tapping B&W tile then Accept passes BwEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-bw')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<BwEnhancer>());
  });

  testWidgets('tapping Color tile then Accept passes ColorEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-color')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<ColorEnhancer>());
  });

  testWidgets('tapping Auto tile then Accept passes AutoEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('filter-tile-original')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('filter-tile-auto')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>());
  });

  testWidgets('saving: true shows spinner and disables Accept', (tester) async {
    // Use pump() not pumpAndSettle(): CircularProgressIndicator is indeterminate
    // and its animation controller never stops, so pumpAndSettle() always times out.
    await tester.pumpWidget(MaterialApp(
      home: CaptureReviewScreen(
        image: const CapturedImage('/nonexistent/g4.jpg'),
        onRetake: () {},
        onAccept: (_, e) {},
        saving: true,
        decodeImageSize: (_) async => const Size(100, 100),
        readBytes: (_) async => Uint8List(0),
      ),
    ));
    await tester.pump(); // schedule async callbacks
    await tester.pump(); // apply state updates

    expect(find.byKey(const Key('review-saving')), findsOneWidget);
    final btn = tester
        .widget<FilledButton>(find.byKey(const Key('review-accept')));
    expect(btn.onPressed, isNull);
  });

  testWidgets('Retake button still present (regression)', (tester) async {
    await _pump(tester, onAccept: (_, e) {});
    expect(find.byKey(const Key('review-retake')), findsOneWidget);
  });
}
