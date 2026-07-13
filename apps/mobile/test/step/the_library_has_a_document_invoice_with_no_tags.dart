import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';

import '../support/fake_library.dart';
import '../support/organize_actions_bdd_state.dart';

/// Usage: the library has a document "Invoice" with no tags
///
/// Seeds an in-memory [FakeDocumentRepository] (shared via [bddOrganizeRepo])
/// with an untagged document named "Invoice". See
/// organize_actions_bdd_state.dart for why this scenario uses a fake
/// repository instead of a real Drift DB.
Future<void> theLibraryHasADocumentInvoiceWithNoTags(
  WidgetTester tester,
) async {
  final repo = bddOrganizeRepo ??= FakeDocumentRepository();

  final doc = Document(
    id: repo.documents.length + 1,
    name: 'Invoice',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  );
  repo.documents.add(doc);
  bddOrganizeDocIdsByName['Invoice'] = doc.id;
}
