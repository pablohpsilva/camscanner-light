import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I see the no matches message
Future<void> iSeeTheNoMatchesMessage(WidgetTester tester) async {
  expect(find.byKey(const Key('documents-search-empty')), findsOneWidget);
}
