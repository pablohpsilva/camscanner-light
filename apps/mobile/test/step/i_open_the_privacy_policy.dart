import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the privacy policy
Future<void> iOpenThePrivacyPolicy(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const Key('settings-privacy')), 300);
  await tester.tap(find.byKey(const Key('settings-privacy')));
  await tester.pumpAndSettle();
}
