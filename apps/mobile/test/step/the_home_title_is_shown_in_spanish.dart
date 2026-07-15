import 'package:flutter_test/flutter_test.dart';

/// Usage: the home title is shown in Spanish
Future<void> theHomeTitleIsShownInSpanish(WidgetTester tester) async {
  expect(find.text('Documentos'), findsOneWidget);
}
