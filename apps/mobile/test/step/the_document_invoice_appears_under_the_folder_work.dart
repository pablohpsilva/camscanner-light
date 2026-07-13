import 'package:flutter_test/flutter_test.dart';

import '../support/organize_actions_bdd_state.dart';

/// Usage: the document "Invoice" appears under the folder "Work"
///
/// Asserts against the repository's own state (not just the widget tree):
/// "Invoice" is filed under a folder literally named "Work".
Future<void> theDocumentInvoiceAppearsUnderTheFolderWork(
  WidgetTester tester,
) async {
  final repo = bddOrganizeRepo!;
  final docId = bddOrganizeDocIdsByName['Invoice']!;

  final folders = await repo.listFolders();
  final workId = folders.singleWhere((f) => f.name == 'Work').id;

  final summaries = await repo.listDocumentSummaries();
  final invoice = summaries.singleWhere((s) => s.document.id == docId);

  expect(invoice.folderId, workId);
}
