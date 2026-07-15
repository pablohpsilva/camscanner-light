import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I choose the system default language
Future<void> iChooseTheSystemDefaultLanguage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('settings-language')));
  await tester.pumpAndSettle();
  final option = find.byKey(const Key('language-option-system'));
  await tester.scrollUntilVisible(
    option,
    80,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.tap(option);
  await tester.pumpAndSettle();
}
