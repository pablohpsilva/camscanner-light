import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the tip thank-you dialog
Future<void> iSeeTheTipThankyouDialog(WidgetTester tester) async {
  expect(find.byKey(const Key('tip-thank-you-dialog')), findsOneWidget);
}
