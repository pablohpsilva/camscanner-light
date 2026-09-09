import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

/// Usage: I open the scanner
///
/// Taps the Home 'Scan' FAB and pumps until the app settles. With the fake
/// scanner the flow resolves immediately: either CaptureReviewScreen is pushed
/// (pages > 0) or ScanScreen pops back to home (0 pages).
Future<void> iOpenTheScanner(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('home-scan')));
  await tester.pumpAndSettle();
}
