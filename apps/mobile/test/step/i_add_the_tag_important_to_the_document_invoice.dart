import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/organize_actions_bdd_state.dart';

/// Usage: I add the tag "Important" to the document "Invoice"
///
/// Opens the document's overflow menu, taps "Tags…", creates a new tag named
/// "Important" inline (which auto-selects it), then confirms with Done.
Future<void> iAddTheTagImportantToTheDocumentInvoice(
  WidgetTester tester,
) async {
  final docId = bddOrganizeDocIdsByName['Invoice']!;

  await tester.tap(find.byKey(Key('document-menu-$docId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('document-tags-$docId')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('manage-tags-new')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('create-tag-field')),
    'Important',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('create-tag-save')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('manage-tags-done')));
  await tester.pumpAndSettle();
}
