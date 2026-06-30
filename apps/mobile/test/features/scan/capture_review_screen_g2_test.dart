import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/bw_enhancer.dart';
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
      image: const CapturedImage('/nonexistent/g2.jpg'),
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
  testWidgets('B&W toggle button is present in the AppBar', (tester) async {
    await _pump(tester, onAccept: (_, _) {});
    expect(find.byKey(const Key('bw-toggle')), findsOneWidget);
  });

  testWidgets('tapping B&W toggle changes its tooltip to B&W on',
      (tester) async {
    await _pump(tester, onAccept: (_, _) {});

    final before =
        tester.widget<IconButton>(find.byKey(const Key('bw-toggle')));
    expect(before.tooltip, equals('B&W off'));

    await tester.tap(find.byKey(const Key('bw-toggle')));
    await tester.pump();

    final after =
        tester.widget<IconButton>(find.byKey(const Key('bw-toggle')));
    expect(after.tooltip, equals('B&W on'));
  });

  testWidgets('Accept with B&W toggle on calls onAccept with BwEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('bw-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<BwEnhancer>());
  });

  testWidgets('Tap grayscale then B&W — only BwEnhancer (mutual exclusion)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('bw-toggle')));
    await tester.pump();

    await tester.tap(find.byKey(const Key('review-accept')));
    expect(captured, isA<BwEnhancer>(),
        reason: 'Tapping B&W must deactivate grayscale');
  });

  testWidgets('Tapping active B&W again deactivates it — NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('bw-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('bw-toggle'))); // deactivate
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>(),
        reason: 'Tapping an active button must turn it off');
  });

  testWidgets('Grayscale toggle still works after G2 (regression)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<GrayscaleEnhancer>(),
        reason: 'Grayscale toggle must remain functional after G2 changes');
  });
}
