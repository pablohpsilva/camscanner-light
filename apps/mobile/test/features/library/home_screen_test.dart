import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/widgets/editor_top_bar.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester,
    FakeDocumentRepository repo,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(repo),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Documents header title', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no documents', (
    tester,
  ) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('lists saved documents when storage is non-empty', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      documents: [
        Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        ),
      ],
    );
    await pumpHome(tester, repo);
    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsOneWidget);
    expect(find.text('No documents yet'), findsNothing);
  });

  testWidgets('shows a tappable Scan action once loaded', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.byKey(const Key('home-scan')), findsOneWidget);
  });

  testWidgets('tapping Scan opens the scan screen', (tester) async {
    // Inject a never-completing scanner so ScanScreen stays visible.
    // pumpAndSettle must NOT be used after tapping — ScanScreen shows a
    // CircularProgressIndicator which keeps scheduling animation frames.
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: ScanDependencies(
            createDocumentScanner: HangingDocumentScannerService.new,
          ),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle(); // initial library load (no scanner involved)
    await tester.tap(find.byKey(const Key('home-scan')));
    await tester
        .pump(); // dispatch tap, push ScanScreen, post-frame _run() starts
    await tester.pump(); // settle pending microtasks; _run() awaits scanner
    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byType(ScanScreen), findsOneWidget);
  });

  testWidgets('shows an error view (not an infinite spinner) when load fails', (
    tester,
  ) async {
    await pumpHome(tester, FakeDocumentRepository(throwOnList: true));
    expect(find.byKey(const Key('documents-loading')), findsNothing);
    expect(find.byKey(const Key('documents-error')), findsOneWidget);
    expect(find.byKey(const Key('documents-retry')), findsOneWidget);
  });

  testWidgets('tapping a document opens the page viewer', (tester) async {
    final repo = FakeDocumentRepository(
      documents: [
        Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        ),
      ],
    );
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();

    expect(find.byType(PageViewerScreen), findsOneWidget);
    expect(
      find.widgetWithText(EditorTopBar, 'Scan 2026-06-27 20.26.42'),
      findsOneWidget,
    );
  });

  testWidgets('renaming from the list menu updates the document name', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      documents: [
        Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        ),
      ],
    );
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'Invoices');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    expect(repo.renamedTo, contains('Invoices'));
    expect(find.text('Invoices'), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsNothing);
  });

  testWidgets('a rename failure shows an error SnackBar', (tester) async {
    final repo = FakeDocumentRepository(
      throwOnRename: true,
      documents: [
        Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
        ),
      ],
    );
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'X');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();

    expect(find.text("Couldn't rename"), findsOneWidget);
  });

  // --- D3: sort control (now the Ream sort pill) ---
  List<Document> twoDocs() => [
    Document(
      id: 1,
      name: 'apple',
      createdAt: DateTime.utc(2026, 1, 1, 10),
      modifiedAt: DateTime.utc(2026, 1, 1, 10),
    ),
    Document(
      id: 2,
      name: 'Zebra',
      createdAt: DateTime.utc(2026, 1, 1, 12), // newer
      modifiedAt: DateTime.utc(2026, 1, 1, 12),
    ),
  ];

  testWidgets('sort pill is hidden when the list is empty', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.byKey(const Key('sort-pill')), findsNothing);
  });

  testWidgets('sort pill is hidden in the error state', (tester) async {
    await pumpHome(tester, FakeDocumentRepository(throwOnList: true));
    expect(find.byKey(const Key('sort-pill')), findsNothing);
    expect(find.byKey(const Key('documents-error')), findsOneWidget);
  });

  testWidgets('sort pill is hidden while loading', (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(listGate: gate, documents: twoDocs());
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(repo),
        ),
      ),
    );
    await tester.pump(); // let _init start; _load is blocked on the gate
    expect(find.byKey(const Key('documents-loading')), findsOneWidget);
    expect(find.byKey(const Key('sort-pill')), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sort-pill')), findsOneWidget);
  });

  testWidgets('sort pill is shown when the library is non-empty', (
    tester,
  ) async {
    await pumpHome(tester, FakeDocumentRepository(documents: twoDocs()));
    expect(find.byKey(const Key('sort-pill')), findsOneWidget);
  });

  testWidgets('default sort is newest-created first', (tester) async {
    await pumpHome(tester, FakeDocumentRepository(documents: twoDocs()));
    // created desc: Zebra (12:00) above apple (10:00).
    final dyZebra = tester.getCenter(find.text('Zebra')).dy;
    final dyApple = tester.getCenter(find.text('apple')).dy;
    expect(dyZebra, lessThan(dyApple));
  });

  testWidgets('picking Name from the sort pill re-orders the list in place', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(documents: twoDocs());
    await pumpHome(tester, repo);
    await tester.tap(find.byKey(const Key('sort-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-option-name')));
    await tester.pumpAndSettle();
    // name asc: apple above Zebra (flips the default order).
    final dyApple = tester.getCenter(find.text('apple')).dy;
    final dyZebra = tester.getCenter(find.text('Zebra')).dy;
    expect(dyApple, lessThan(dyZebra));
  });

  testWidgets('renaming under an active Name sort re-positions the document', (
    tester,
  ) async {
    // Distinct names AND timestamps so the Name-asc order differs from the
    // default (created-desc) order — that gap is what lets this test tell
    // "sort survived _load()" apart from "sort silently reverted to default".
    final repo = FakeDocumentRepository(
      documents: [
        Document(
          id: 1,
          name: 'zzz',
          createdAt: DateTime.utc(2026, 1, 1, 10), // older
          modifiedAt: DateTime.utc(2026, 1, 1, 10),
        ),
        Document(
          id: 2,
          name: 'mmm',
          createdAt: DateTime.utc(2026, 1, 1, 12), // newer
          modifiedAt: DateTime.utc(2026, 1, 1, 12),
        ),
      ],
    );
    await pumpHome(tester, repo);
    // Activate Name sort (asc): mmm above zzz.
    await tester.tap(find.byKey(const Key('sort-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-option-name')));
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.text('mmm')).dy,
      lessThan(tester.getCenter(find.text('zzz')).dy),
    );
    // Rename 'zzz' (id 1, the OLDER doc) to 'aaa' via its row menu.
    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'aaa');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();
    expect(find.text('zzz'), findsNothing);
    // Under Name-asc, 'aaa' < 'mmm' -> aaa on top. The DEFAULT (created-desc)
    // would instead put mmm (newer) on top, so this assertion FAILS if the sort
    // reverted to default. It therefore proves BOTH repositioning (id1 moved
    // bottom->top) AND that the active Name sort survived _load().
    expect(
      tester.getCenter(find.text('aaa')).dy,
      lessThan(tester.getCenter(find.text('mmm')).dy),
      reason: 'renamed doc re-positions under the still-active Name sort',
    );
  });

  testWidgets('sorting does not trigger a repository re-query', (tester) async {
    final repo = FakeDocumentRepository(documents: twoDocs());
    await pumpHome(tester, repo);
    final callsAfterLoad = repo.listCalls;
    await tester.tap(find.byKey(const Key('sort-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-option-name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-pill')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-option-name'))); // flip
    await tester.pumpAndSettle();
    expect(
      repo.listCalls,
      callsAfterLoad,
      reason: 'sorting is in-memory; no listDocumentSummaries re-query',
    );
  });

  testWidgets(
    'library-view-toggle switches to the grid and shows a saved doc card',
    (tester) async {
      final repo = FakeDocumentRepository(
        documents: [
          Document(
            id: 1,
            name: 'Scan 2026-06-27 20.26.42',
            createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
            modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          ),
        ],
      );
      await pumpHome(tester, repo);
      expect(find.byKey(const Key('documents-list')), findsOneWidget);
      expect(find.byKey(const Key('documents-grid')), findsNothing);

      await tester.tap(find.byKey(const Key('segment-grid')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('documents-grid')), findsOneWidget);
      expect(find.byKey(const Key('documents-list')), findsNothing);
      expect(find.text('Scan 2026-06-27 20.26.42'), findsOneWidget);
    },
  );
}
