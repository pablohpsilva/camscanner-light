import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the original filter tile
Future<void> iTapTheOriginalFilterTile(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('filter-tile-original')));
  await tester.pump();
}
