import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the support row
Future<void> iSeeTheSupportRow(WidgetTester tester) async {
  expect(find.byKey(const Key('settings-support')), findsOneWidget);
}
