import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap Done
Future<void> iTapDone(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('camera-done')));
  await tester.pumpAndSettle();
}
