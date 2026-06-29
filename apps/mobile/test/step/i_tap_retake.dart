import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap Retake
Future<void> iTapRetake(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('review-retake')));
  await tester.pumpAndSettle();
}
