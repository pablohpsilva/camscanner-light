import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the crop overlay
Future<void> iSeeTheCropOverlay(WidgetTester tester) async {
  await tester.pumpAndSettle(); // wait for the natural-size decode
  expect(find.byKey(const Key('crop-overlay')), findsOneWidget);
}
