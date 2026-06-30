import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the grayscale filter tile
Future<void> iTapTheGrayscaleFilterTile(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-grayscale')));
  await tester.pump();
}
