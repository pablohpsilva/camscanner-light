import 'package:flutter_test/flutter_test.dart';

import '../support/app_l10n.dart';

/// Usage: I see the no text to copy message
///
/// Asserts HomeScreen._copyText took its EMPTY branch: the document carries no
/// recognized text, so the handler says so instead of quietly writing an empty
/// clipboard. That "never silently write an empty clipboard" guarantee is the
/// whole point of the branch, and nothing exercised it before.
///
/// Resolved through [l10nOf] rather than hardcoded — the app follows the device
/// language and this repo's test iPhone runs in Luxembourgish.
Future<void> iSeeTheNoTextToCopyMessage(WidgetTester tester) async {
  final l10n = l10nOf(tester);
  expect(find.text(l10n.copyTextEmpty), findsOneWidget);
}
