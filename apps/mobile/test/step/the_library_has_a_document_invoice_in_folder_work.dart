import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';

import '../support/fake_library.dart';
import '../support/folder_filter_bdd_state.dart';

/// Usage: the library has a document "Invoice" in folder "Work"
///
/// Seeds an in-memory [FakeDocumentRepository] (created lazily and shared via
/// [bddFolderRepo] with any other seed step in the same scenario) with a
/// document assigned to the named folder, creating the folder first if this
/// is the first document seeded into it. See folder_filter_bdd_state.dart for
/// why this scenario uses a fake repository instead of a real Drift DB.
Future<void> theLibraryHasADocumentInvoiceInFolderWork(
  WidgetTester tester,
) async {
  final repo = bddFolderRepo ??= FakeDocumentRepository();

  var folderId = bddFolderIdsByName['Work'];
  if (folderId == null) {
    final folder = await repo.createFolder('Work');
    folderId = folder.id;
    bddFolderIdsByName['Work'] = folderId;
  }

  final doc = Document(
    id: repo.documents.length + 1,
    name: 'Invoice',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  );
  repo.documents.add(doc);
  await repo.moveToFolder(doc.id, folderId);
}
