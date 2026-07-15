import 'package:flutter_test/flutter_test.dart';

/// Usage: the home title is shown in Brazilian Portuguese
Future<void> theHomeTitleIsShownInBrazilianPortuguese(
  WidgetTester tester,
) async {
  expect(find.text('Documentos'), findsOneWidget);
}
