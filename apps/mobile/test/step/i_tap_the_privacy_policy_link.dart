import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Usage: I tap the privacy policy link
///
/// The terms document's "acceptance" section links to the Privacy Policy
/// (`[Privacy Policy](privacy.html)`); `LegalDocumentScreen` intercepts
/// sibling-document filenames and pushes the target document in-app instead
/// of handing them to the URL opener.
Future<void> iTapThePrivacyPolicyLink(WidgetTester tester) async {
  final section = find.byKey(const Key('legal-section-acceptance'));
  await tester.scrollUntilVisible(section, 300);
  final link = find.descendant(
    of: section,
    matching: find.text('Privacy Policy'),
  );
  await tester.scrollUntilVisible(link, 300);
  await tester.tap(link);
  await tester.pumpAndSettle();
}
