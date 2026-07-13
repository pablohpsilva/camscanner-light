import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/organize_actions_bdd_state.dart';

/// Usage: I move the document "Invoice" to a new folder "Work"
///
/// Opens the document's overflow menu, taps "Move to folder", creates a new
/// folder named "Work" inline, then selects it — driving the same UI path a
/// real user takes (document-menu -> Move to folder -> New folder… -> pick).
Future<void> iMoveTheDocumentInvoiceToANewFolderWork(
  WidgetTester tester,
) async {
  final docId = bddOrganizeDocIdsByName['Invoice']!;

  await tester.tap(find.byKey(Key('document-menu-$docId')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(Key('document-move-$docId')));
  await tester.pumpAndSettle();

  await tester.tap(find.byKey(const Key('move-to-folder-new')));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(const Key('create-folder-field')),
    'Work',
  );
  await tester.pump();
  await tester.tap(find.byKey(const Key('create-folder-save')));
  await tester.pumpAndSettle();

  final repo = bddOrganizeRepo!;
  final folders = await repo.listFolders();
  final workId = folders.singleWhere((f) => f.name == 'Work').id;
  await tester.tap(find.byKey(Key('move-to-folder-$workId')));
  await tester.pumpAndSettle();
}
