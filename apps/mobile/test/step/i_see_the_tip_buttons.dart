import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the tip buttons
Future<void> iSeeTheTipButtons(WidgetTester tester) async {
  expect(find.byKey(const Key('tip-button-tip_small')), findsOneWidget);
}
