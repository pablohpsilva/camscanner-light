import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the tip unavailable message
Future<void> iSeeTheTipUnavailableMessage(WidgetTester tester) async {
  expect(find.byKey(const Key('tip-unavailable')), findsOneWidget);
}
