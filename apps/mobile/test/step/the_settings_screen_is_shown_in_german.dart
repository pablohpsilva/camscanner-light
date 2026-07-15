import 'package:flutter_test/flutter_test.dart';

/// Usage: the settings screen is shown in German
Future<void> theSettingsScreenIsShownInGerman(WidgetTester tester) async {
  expect(find.text('Einstellungen'), findsOneWidget);
}
