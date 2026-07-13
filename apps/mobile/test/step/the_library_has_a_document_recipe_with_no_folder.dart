import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';

import '../support/fake_library.dart';
import '../support/folder_filter_bdd_state.dart';

/// Usage: the library has a document "Recipe" with no folder
///
/// Seeds an in-memory [FakeDocumentRepository] (shared via [bddFolderRepo])
/// with an unfiled document (no folder assignment). See
/// folder_filter_bdd_state.dart for why this scenario uses a fake repository
/// instead of a real Drift DB.
Future<void> theLibraryHasADocumentRecipeWithNoFolder(
  WidgetTester tester,
) async {
  final repo = bddFolderRepo ??= FakeDocumentRepository();

  final doc = Document(
    id: repo.documents.length + 1,
    name: 'Recipe',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
  );
  repo.documents.add(doc);
}
