import 'package:flutter_test/flutter_test.dart';

/// Usage: the home title is shown in English
Future<void> theHomeTitleIsShownInEnglish(WidgetTester tester) async {
  expect(find.text('Documents'), findsOneWidget);
}
