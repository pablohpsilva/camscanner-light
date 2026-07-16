import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/widgets/documents_list_view.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';
import '../../support/localized_app.dart';

/// P12 T12.4: the sorted library list is cached and recomputed only when
/// `_summaries` or `_sort` changes — NOT on every unrelated `setState`. We prove
/// this via the list instance handed to [DocumentsListView]: an unrelated
/// rebuild (entering selection mode) must reuse the SAME sorted list instance,
/// whereas sorting-on-build would hand a freshly-sorted list each build.
void main() {
  Future<void> pumpHome(
    WidgetTester tester,
    FakeDocumentRepository repo,
  ) async {
    await tester.pumpWidget(
      localizedTestApp(
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<DocumentSummary> summariesInstance(WidgetTester tester) => tester
      .widget<DocumentsListView>(find.byType(DocumentsListView))
      .summaries;

  testWidgets('an unrelated rebuild (entering selection) reuses the cached '
      'sorted list instance', (tester) async {
    final repo = FakeDocumentRepository(
      documents: [
        Document(
          id: 1,
          name: 'Alpha',
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 1, 1),
        ),
        Document(
          id: 2,
          name: 'Bravo',
          createdAt: DateTime.utc(2026, 2, 1),
          modifiedAt: DateTime.utc(2026, 2, 1),
        ),
      ],
    );
    await pumpHome(tester, repo);

    final before = summariesInstance(tester);
    expect(before.length, 2);

    // Long-press a tile to enter selection mode — a setState that changes
    // neither _summaries nor _sort.
    await tester.longPress(find.text('Alpha'));
    await tester.pumpAndSettle();

    final after = summariesInstance(tester);
    expect(
      identical(before, after),
      isTrue,
      reason: 'sorted list must be cached, not recomputed on every build',
    );
  });
}
