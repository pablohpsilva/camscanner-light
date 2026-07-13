import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';

import '../support/fake_library.dart';
import '../support/organize_actions_bdd_state.dart';

/// Usage: the library has a document "Scan 1" whose page has OCR text suggesting "INVOICE"
///
/// Seeds an in-memory [FakeDocumentRepository] (shared via [bddOrganizeRepo],
/// same pattern as the other "the library has a document ..." seed steps)
/// with a document and a CANNED suggestTitleFor result. The fake repository
/// has no OCR/TitleSuggester pipeline, so this seeds the suggestion directly
/// rather than faking OCR end-to-end (the TitleSuggester itself is covered by
/// its own unit tests).
Future<void> theLibraryHasADocumentScan1WhosePageHasOcrTextSuggestingInvoice(
  WidgetTester tester,
) async {
  final repo = bddOrganizeRepo ??= FakeDocumentRepository();

  final doc = Document(
    id: repo.documents.length + 1,
    name: 'Scan 1',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  );
  repo.documents.add(doc);
  bddOrganizeDocIdsByName['Scan 1'] = doc.id;
  repo.suggestedTitles[doc.id] = 'INVOICE';
}
