import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the terms of service
Future<void> iOpenTheTermsOfService(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const Key('settings-terms')), 300);
  await tester.tap(find.byKey(const Key('settings-terms')));
  await tester.pumpAndSettle();
}
