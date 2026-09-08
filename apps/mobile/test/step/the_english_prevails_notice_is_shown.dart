import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: the English prevails notice is shown
Future<void> theEnglishPrevailsNoticeIsShown(WidgetTester tester) async {
  expect(find.byKey(const Key('legal-translation-notice')), findsOneWidget);
}
