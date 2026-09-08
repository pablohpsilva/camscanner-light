import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I open the faq
Future<void> iOpenTheFaq(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byKey(const Key('settings-faq')), 300);
  await tester.tap(find.byKey(const Key('settings-faq')));
  await tester.pumpAndSettle();
}
