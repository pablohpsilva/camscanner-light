import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I do not see the Ko-fi button
Future<void> iDoNotSeeTheKofiButton(WidgetTester tester) async {
  expect(find.byKey(const Key('donation-kofi-button')), findsNothing);
}
