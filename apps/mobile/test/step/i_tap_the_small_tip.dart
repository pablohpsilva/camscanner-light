import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the small tip
Future<void> iTapTheSmallTip(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('tip-button-tip_small')));
  await tester.pumpAndSettle();
}
