import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> iSeeThePageViewer(WidgetTester tester) async {
  await tester.pumpAndSettle();
  // page-viewer-page-1: pages are 1-indexed (position=1 for the first page).
  // The spec mentions page-viewer-page-0 — that is a spec typo.
  expect(find.byKey(const Key('page-viewer-page-1')), findsOneWidget);
}
