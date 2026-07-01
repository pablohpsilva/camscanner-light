import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I capture and accept the second page
Future<void> iCaptureAndAcceptTheSecondPage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('scan-shutter')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('review-accept')));
  await tester.pumpAndSettle();
}
