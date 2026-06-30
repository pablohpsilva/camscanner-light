import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the filter picker strip
Future<void> iSeeTheFilterPickerStrip(WidgetTester tester) async {
  expect(find.byKey(const Key('filter-picker-strip')), findsOneWidget,
      reason: 'FilterPickerStrip must be visible on the review screen');
}
