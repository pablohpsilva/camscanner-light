import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/enhancer_mode.dart';
import 'package:mobile/features/scan/widgets/filter_picker_strip.dart';

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
  });
}
