import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the black and white filter
Future<void> iToggleTheBlackAndWhiteFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('bw-toggle')));
  await tester.pump();
}
