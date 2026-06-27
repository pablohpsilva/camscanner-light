import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the shutter
Future<void> iTapTheShutter(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('scan-shutter')));
  await tester.pumpAndSettle();
}
