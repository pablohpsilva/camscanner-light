import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/scan/widgets/filter_picker_strip.dart';

import '../../../support/fake_scan.dart';

Future<void> _pump(
  WidgetTester tester, {
  EnhancerMode selectedMode = EnhancerMode.auto,
  void Function(EnhancerMode)? onModeChanged,
  Uint8List? sourceBytes,
}) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FilterPickerStrip(
        selectedMode: selectedMode,
        onModeChanged: onModeChanged ?? (_) {},
        sourceBytes: sourceBytes,
      ),
    ),
  ));
}

void main() {
  group('FilterPickerStrip', () {
    testWidgets('shows all five filter tiles when sourceBytes is null',
        (tester) async {
      await _pump(tester);
      expect(find.byKey(const Key('filter-tile-auto')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-original')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-color')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-grayscale')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-bw')), findsOneWidget);
    });

    testWidgets('tapping Grayscale tile calls onModeChanged with .grayscale',
        (tester) async {
      EnhancerMode? captured;
      await _pump(tester, onModeChanged: (m) => captured = m);

      await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
      await tester.pump();

      expect(captured, EnhancerMode.grayscale);
    });

    testWidgets(
        'tapping Original tile calls onModeChanged with .none (no enhancement)',
        (tester) async {
      EnhancerMode? captured;
      await _pump(tester, onModeChanged: (m) => captured = m);

      await tester.tap(find.byKey(const Key('filter-tile-original')));
      await tester.pump();

      expect(captured, EnhancerMode.none);
    });

    testWidgets('selected tile has a border decoration', (tester) async {
      await _pump(tester, selectedMode: EnhancerMode.grayscale);

      final container = tester
          .widget<Container>(find.byKey(const Key('filter-tile-grayscale')));
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNotNull,
          reason: 'Selected tile must have a border');
    });

    testWidgets('unselected tile has no border', (tester) async {
      await _pump(tester, selectedMode: EnhancerMode.auto);

      final container =
          tester.widget<Container>(find.byKey(const Key('filter-tile-bw')));
      final decoration = container.decoration as BoxDecoration?;
      expect(decoration?.border, isNull,
          reason: 'Unselected tile must not have a border');
    });

    testWidgets('does not crash when sourceBytes is corrupt', (tester) async {
      final corrupt = Uint8List.fromList([0, 1, 2, 3, 99]);
      await _pump(tester, sourceBytes: corrupt);
      await tester.pumpAndSettle();
      // All 5 tiles still present after failed generation
      expect(find.byKey(const Key('filter-tile-auto')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-bw')), findsOneWidget);
    });

    // Regression: c2777d7 — _maybeGenerate left _generating=true forever when
    // thumbnail generation failed on a degenerate image (e.g. the 1×1 JPEG),
    // freezing every tile as a CircularProgressIndicator.  The fix wraps the
    // generation body in try/catch/finally so the flag is always cleared.
    testWidgets(
        'spinner clears after generation settles on degenerate 1×1 image '
        '(regression c2777d7: finally block always clears _generating)',
        (tester) async {
      // Use kFakeJpegBytes (a valid 1×1 JPEG from fake_scan.dart).
      // The downsample step succeeds, but such a degenerate image exercises
      // the async compute() / Future.wait path that was never guarded with a
      // finally in the pre-fix code.
      //
      // tester.runAsync lets real Dart isolates (spawned by compute()) run to
      // completion — plain pumpAndSettle() runs in the fake-async zone and
      // would never advance real isolates, hanging on the spinner animation.
      await tester.runAsync(() async {
        await _pump(tester, sourceBytes: kFakeJpegBytes);
        // Give compute() isolates and enhancer futures time to finish.
        await Future.delayed(const Duration(seconds: 5));
      });

      // Pump once more to flush any pending setState rebuilds scheduled while
      // the isolates were running inside runAsync.
      await tester.pump();

      // After generation settles (success OR failure), _generating must be
      // false so no tile is stuck on a CircularProgressIndicator.
      expect(
        find.byType(CircularProgressIndicator),
        findsNothing,
        reason: 'All tiles must show either a thumbnail or a fallback icon — '
            'never a spinner — after generation finishes.',
      );

      // All five tiles are still present in the tree.
      expect(find.byKey(const Key('filter-tile-auto')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-original')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-color')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-grayscale')), findsOneWidget);
      expect(find.byKey(const Key('filter-tile-bw')), findsOneWidget);
    });
  });
}
