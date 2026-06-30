import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I toggle the grayscale filter
Future<void> iToggleTheGrayscaleFilter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('grayscale-toggle')));
  await tester.pump();
}
