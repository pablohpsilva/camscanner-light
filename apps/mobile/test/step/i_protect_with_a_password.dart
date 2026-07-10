import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I protect with a password
Future<void> iProtectWithAPassword(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('page-viewer-share')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('page-viewer-protect')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('password-field')), 'secret');
  await tester.pump();
  await tester.tap(find.byKey(const Key('password-confirm')));
  await tester.pumpAndSettle();
}
