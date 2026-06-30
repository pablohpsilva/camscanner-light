import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the color filter
Future<void> iToggleTheColorFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-color')));
  await tester.pump();
}
