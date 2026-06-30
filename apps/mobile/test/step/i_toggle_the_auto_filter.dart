import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the auto filter
Future<void> iToggleTheAutoFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-auto')));
  await tester.pump();
}
