import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I select right-handed
Future<void> iSelectRighthanded(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('segment-Handedness.right')));
  await tester.pumpAndSettle();
}
