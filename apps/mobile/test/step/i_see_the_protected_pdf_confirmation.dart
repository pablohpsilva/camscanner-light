import 'package:flutter_test/flutter_test.dart';
import '../support/app_l10n.dart';

/// Usage: I see the protected PDF confirmation
Future<void> iSeeTheProtectedPdfConfirmation(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 100));
  expect(find.text(l10nOf(tester).viewerProtectPdfSuccess), findsOneWidget);
}
