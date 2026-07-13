// Branch coverage for HomeScreen: retry after a startup failure (lines
// 148-154), the post-scan / post-ID-scan / post-document-viewer refresh calls
// (lines 166, 178, 253), the import Retake callback (line 211), the import
// save-failure SnackBar (line 220), and the search-failure branch (line 270).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/document_summary.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/scan/capture_review_screen.dart';
import 'package:mobile/features/scan/id_scan_screen.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

/// A repository whose listDocumentSummaries() throws exactly once (the first
/// cold-start call), then succeeds — so the error screen appears, and a Retry
/// can be proven to recover into the loaded state.
class _FailOnceRepository extends FakeDocumentRepository {
  int _calls = 0;
  _FailOnceRepository({super.documents});

  @override
  Future<List<DocumentSummary>> listDocumentSummaries() async {
    _calls++;
    if (_calls == 1) throw StateError('fake: first load failed');
    return super.listDocumentSummaries();
  }
}

void main() {
  Future<void> pumpHome(
    WidgetTester tester,
    FakeDocumentRepository repo, {
    ScanDependencies? deps,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: deps ?? grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'Retry after a startup failure clears the error and reloads the library',
    (tester) async {
      final repo = _FailOnceRepository(
        documents: [
          Document(
            id: 1,
            name: 'Recovered Doc',
            createdAt: DateTime.utc(2026, 1, 1),
            modifiedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      await pumpHome(tester, repo);

      expect(find.byKey(const Key('documents-error')), findsOneWidget);
      expect(find.byKey(const Key('documents-retry')), findsOneWidget);

      await tester.tap(find.byKey(const Key('documents-retry')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents-error')), findsNothing);
      expect(find.text('Recovered Doc'), findsOneWidget);
    },
  );

  testWidgets('returning from the Scan flow refreshes the document list', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    // A scanner that immediately returns no pages -> ScanScreen pops itself,
    // exercising the _openScan() -> await push -> _refresh() path.
    final deps = ScanDependencies(
      createDocumentScanner: () => FakeDocumentScannerService(const []),
      createGalleryPicker: () => const FakeGalleryPicker(),
    );
    await pumpHome(tester, repo, deps: deps);
    final callsBefore = repo.listCalls;

    await tester.tap(find.byKey(const Key('home-scan')));
    await tester.pumpAndSettle();

    expect(find.byType(ScanScreen), findsNothing, reason: 'popped back home');
    expect(
      repo.listCalls,
      greaterThan(callsBefore),
      reason: '_refresh() re-queried the repository after the scan flow',
    );
  });

  testWidgets('returning from the ID scan flow refreshes the document list', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    // Sequential scanner returns empty results for both front and back ->
    // IdScanScreen pops on the first (front) step without saving, exercising
    // _openIdScan() -> await push -> _refresh().
    final deps = ScanDependencies(
      createDocumentScanner: () =>
          FakeSequentialDocumentScannerService(const [[], []]),
      createGalleryPicker: () => const FakeGalleryPicker(),
    );
    await pumpHome(tester, repo, deps: deps);
    final callsBefore = repo.listCalls;

    await tester.tap(find.byKey(const Key('home-scan-id')));
    await tester.pumpAndSettle();

    expect(find.byType(IdScanScreen), findsNothing);
    expect(
      repo.listCalls,
      greaterThan(callsBefore),
      reason: '_refresh() re-queried the repository after the ID scan flow',
    );
  });

  testWidgets('tapping Retake in the import review pops back without saving', (
    tester,
  ) async {
    final repo = FakeDocumentRepository();
    final deps = ScanDependencies(
      createGalleryPicker: () =>
          const FakeGalleryPicker(returnPath: '/nonexistent/import.jpg'),
      createEdgeDetector: FakeEdgeDetector.new,
    );
    await pumpHome(tester, repo, deps: deps);

    await tester.tap(find.byKey(const Key('home-import')));
    await tester.pumpAndSettle();
    expect(find.byType(CaptureReviewScreen), findsOneWidget);

    await tester.tap(find.byKey(const Key('review-retake')));
    await tester.pumpAndSettle();

    expect(find.byType(CaptureReviewScreen), findsNothing);
    expect(repo.createCalls, 0, reason: 'Retake must not save anything');
  });

  testWidgets(
    'a save failure in the import review shows an error SnackBar and stays open',
    (tester) async {
      final repo = FakeDocumentRepository(throwOnCreate: true);
      final deps = ScanDependencies(
        createGalleryPicker: () =>
            const FakeGalleryPicker(returnPath: '/nonexistent/import.jpg'),
        createEdgeDetector: FakeEdgeDetector.new,
      );
      await pumpHome(tester, repo, deps: deps);

      await tester.tap(find.byKey(const Key('home-import')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('review-accept')));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't save document. Try again."), findsOneWidget);
      expect(
        find.byType(CaptureReviewScreen),
        findsOneWidget,
        reason: 'a failed save keeps the review screen open (no pop)',
      );
    },
  );

  testWidgets(
    'reopening the library after viewing a document refreshes the list',
    (tester) async {
      final repo = FakeDocumentRepository(
        documents: [
          Document(
            id: 1,
            name: 'Scan A',
            createdAt: DateTime.utc(2026, 1, 1),
            modifiedAt: DateTime.utc(2026, 1, 1),
          ),
        ],
      );
      await pumpHome(tester, repo);
      final callsBefore = repo.listCalls;

      await tester.tap(find.byKey(const Key('document-tile-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('page-viewer-back')));
      await tester.pumpAndSettle();

      expect(
        repo.listCalls,
        greaterThan(callsBefore),
        reason: '_refresh() re-queried after popping the page viewer',
      );
    },
  );

  testWidgets('a search failure sets the error state', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnList: true,
      documents: [
        Document(
          id: 1,
          name: 'Doc',
          createdAt: DateTime.utc(2026, 1, 1),
          modifiedAt: DateTime.utc(2026, 1, 1),
        ),
      ],
    );
    // throwOnList also makes searchDocuments() throw in FakeDocumentRepository,
    // but the initial listDocumentSummaries() call must succeed first so the
    // search field is reachable — use a wrapper that only fails search.
    final searchFailRepo = _SearchFailsRepository(documents: repo.documents);
    await pumpHome(tester, searchFailRepo);
    expect(find.byKey(const Key('documents-error')), findsNothing);

    await tester.enterText(find.byType(TextField), 'anything');
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('documents-error')), findsOneWidget);
  });
}

/// listDocumentSummaries() succeeds (so cold start completes normally), but
/// searchDocuments() always throws — isolates HomeScreen's search-error catch
/// branch (line 270) from the cold-start error branch, which uses throwOnList
/// for both calls in the shared fake.
class _SearchFailsRepository extends FakeDocumentRepository {
  _SearchFailsRepository({super.documents});

  @override
  Future<List<DocumentSummary>> searchDocuments(String query) async {
    throw StateError('fake: search failed');
  }
}
