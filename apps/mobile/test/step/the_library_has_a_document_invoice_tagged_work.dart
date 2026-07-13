import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';

import '../support/fake_library.dart';
import '../support/tag_filter_bdd_state.dart';

/// Usage: the library has a document "Invoice" tagged "Work"
///
/// Seeds an in-memory [FakeDocumentRepository] (created lazily and shared via
/// [bddTagRepo] with any other seed step in the same scenario) with a
/// document carrying the named tag, creating the tag first if this is the
/// first document seeded with it. See tag_filter_bdd_state.dart for why this
/// scenario uses a fake repository instead of a real Drift DB.
Future<void> theLibraryHasADocumentInvoiceTaggedWork(
  WidgetTester tester,
) async {
  final repo = bddTagRepo ??= FakeDocumentRepository();

  var tagId = bddTagIdsByName['Work'];
  if (tagId == null) {
    final tag = await repo.createTag('Work');
    tagId = tag.id;
    bddTagIdsByName['Work'] = tagId;
  }

  final doc = Document(
    id: repo.documents.length + 1,
    name: 'Invoice',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  );
  repo.documents.add(doc);
  await repo.setDocumentTags(doc.id, {tagId});
}
