import 'package:flutter_test/flutter_test.dart';

import '../support/app_l10n.dart';

/// Usage: I see the copy text confirmation
///
/// Asserts HomeScreen._copyText reached its success branch — the document had
/// recognized text, it went to the clipboard, and the confirmation snackbar
/// showed. The host swipe BDD only proves the LIST WIDGET fired its callback
/// (see swipe_test_harness); this proves the real handler ran.
///
/// Resolved through [l10nOf] rather than hardcoded: the app follows the device
/// language and this repo's test iPhone runs in Luxembourgish.
Future<void> iSeeTheCopyTextConfirmation(WidgetTester tester) async {
  final l10n = l10nOf(tester);
  expect(find.text(l10n.copyTextDone), findsOneWidget);
}
