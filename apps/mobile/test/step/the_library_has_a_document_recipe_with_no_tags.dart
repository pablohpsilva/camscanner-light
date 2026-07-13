import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';

import '../support/fake_library.dart';
import '../support/tag_filter_bdd_state.dart';

/// Usage: the library has a document "Recipe" with no tags
///
/// Seeds an in-memory [FakeDocumentRepository] (shared via [bddTagRepo]) with
/// an untagged document. See tag_filter_bdd_state.dart for why this scenario
/// uses a fake repository instead of a real Drift DB.
Future<void> theLibraryHasADocumentRecipeWithNoTags(WidgetTester tester) async {
  final repo = bddTagRepo ??= FakeDocumentRepository();

  final doc = Document(
    id: repo.documents.length + 1,
    name: 'Recipe',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
  );
  repo.documents.add(doc);
}
