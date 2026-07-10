import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I accept the captured back
Future<void> iAcceptTheCapturedBack(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}
