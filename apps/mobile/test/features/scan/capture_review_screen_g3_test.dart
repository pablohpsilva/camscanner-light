import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/auto_enhancer.dart';
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
      image: const CapturedImage('/nonexistent/g3.jpg'),
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
  testWidgets('Auto and Color toggle buttons are present in the AppBar',
      (tester) async {
    await _pump(tester, onAccept: (_, e) {});
    expect(find.byKey(const Key('auto-toggle')), findsOneWidget);
    expect(find.byKey(const Key('color-toggle')), findsOneWidget);
  });

  testWidgets('Tapping Auto changes its tooltip to "Auto on"', (tester) async {
    await _pump(tester, onAccept: (_, e) {});

    final before = tester.widget<IconButton>(find.byKey(const Key('auto-toggle')));
    expect(before.tooltip, equals('Auto off'));

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();

    final after = tester.widget<IconButton>(find.byKey(const Key('auto-toggle')));
    expect(after.tooltip, equals('Auto on'));
  });

  testWidgets('Tapping Color changes its tooltip to "Color on"', (tester) async {
    await _pump(tester, onAccept: (_, e) {});

    final before = tester.widget<IconButton>(find.byKey(const Key('color-toggle')));
    expect(before.tooltip, equals('Color off'));

    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();

    final after = tester.widget<IconButton>(find.byKey(const Key('color-toggle')));
    expect(after.tooltip, equals('Color on'));
  });

  testWidgets('Accept with Auto on calls onAccept with AutoEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>());
  });

  testWidgets('Accept with Color on calls onAccept with ColorEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<ColorEnhancer>());
  });

  testWidgets('Tap Grayscale then Auto — only AutoEnhancer (mutual exclusion)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<AutoEnhancer>(),
        reason: 'Tapping Auto must deactivate Grayscale');
  });

  testWidgets('Tap Auto then Color — only ColorEnhancer (mutual exclusion)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<ColorEnhancer>(),
        reason: 'Tapping Color must deactivate Auto');
  });

  testWidgets('Tapping active Auto again deactivates it — NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('auto-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>(),
        reason: 'Tapping active Auto must toggle it off');
  });

  testWidgets('Tapping active Color again deactivates it — NoneEnhancer',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('color-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<NoneEnhancer>(),
        reason: 'Tapping active Color must toggle it off');
  });

  testWidgets('Grayscale toggle still works after G3 (regression)',
      (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('grayscale-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isA<GrayscaleEnhancer>(),
        reason: 'Grayscale toggle must remain functional after G3 changes');
  });

  testWidgets('B&W toggle still works after G3 (regression)', (tester) async {
    ImageEnhancer? captured;
    await _pump(tester, onAccept: (_, e) => captured = e);

    await tester.tap(find.byKey(const Key('bw-toggle')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('review-accept')));

    expect(captured, isNot(isA<NoneEnhancer>()),
        reason: 'B&W toggle must remain functional after G3 changes');
  });
}
