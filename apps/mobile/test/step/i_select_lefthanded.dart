import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select left-handed
Future<void> iSelectLefthanded(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-Handedness.left')));
  await tester.pumpAndSettle();
}
