import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> theFirstVisiblePageIsPosition2(WidgetTester tester) async {
  expect(find.byKey(const Key('page-viewer-page-2')), findsOneWidget);
}
