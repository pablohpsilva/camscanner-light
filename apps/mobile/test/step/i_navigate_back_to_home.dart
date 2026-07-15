import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I navigate back to home
///
/// Pops the current screen via the Ream back header. Needed before an
/// in-test relaunch: a second runCamScannerApp pump updates the existing
/// element tree in place, so the Navigator KEEPS its route stack — the
/// relaunched UI only shows home if home was already the top route.
Future<void> iNavigateBackToHome(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('ream-back')));
  await tester.pumpAndSettle();
  expect(find.byKey(const Key('home-settings')), findsOneWidget);
}
