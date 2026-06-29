import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap Accept
Future<void> iTapAccept(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}
