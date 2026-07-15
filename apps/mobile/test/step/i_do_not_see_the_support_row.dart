import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the support row
Future<void> iDoNotSeeTheSupportRow(WidgetTester tester) async {
  expect(find.byKey(const Key('settings-support')), findsNothing);
}
