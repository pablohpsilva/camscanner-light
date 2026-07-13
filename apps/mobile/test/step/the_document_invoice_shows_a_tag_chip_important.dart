import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/widgets/tag_chips.dart';

import '../support/organize_actions_bdd_state.dart';

/// Usage: the document "Invoice" shows a tag chip "Important"
///
/// Asserts the tag chip is rendered in the document's list row (the visible
/// UI proof, not just the repository's state — the row only shows tag chips
/// once [_refresh] has re-loaded the document's tags after Done).
Future<void> theDocumentInvoiceShowsATagChipImportant(
  WidgetTester tester,
) async {
  await tester.pumpAndSettle();
  final docId = bddOrganizeDocIdsByName['Invoice']!;

  expect(
    find.descendant(
      of: find.byKey(Key('document-tile-$docId')),
      matching: find.byType(TagChips),
    ),
    findsOneWidget,
  );
  expect(find.text('Important'), findsOneWidget);
}
