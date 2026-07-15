import 'package:flutter_test/flutter_test.dart';

/// Usage: the settings screen is shown in Spanish
Future<void> theSettingsScreenIsShownInSpanish(WidgetTester tester) async {
  expect(find.text('Ajustes'), findsOneWidget);
}
