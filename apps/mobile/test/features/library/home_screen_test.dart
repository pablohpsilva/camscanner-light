import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/feature_flags.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/page_viewer_screen.dart';
import 'package:mobile/features/library/widgets/editor_top_bar.dart';
import 'package:mobile/features/scan/scan_dependencies.dart';
import 'package:mobile/features/scan/scan_screen.dart';
import 'package:mobile/theme/ream_colors.dart';
import 'package:mobile/theme/ream_theme.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(
    WidgetTester tester,
    FakeDocumentRepository repo, {
    FeatureFlags features = const FeatureFlags(),
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.light(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            repo,
            features: features,
          ),
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

  testWidgets('HomeScreen uses dark paper under the dark theme', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ReamTheme.dark(),
        home: HomeScreen(
          dependencies: grantedScanDependencies(),
          libraryDependencies: fakeLibraryDependencies(
            FakeDocumentRepository(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // HomeScreen's Scaffold doesn't set an explicit backgroundColor; it
    // inherits ThemeData.scaffoldBackgroundColor (set from ReamColors.paper
    // in ReamTheme._build), so assert that resolved value instead.
    expect(
      Theme.of(
        tester.element(find.byType(Scaffold).first),
      ).scaffoldBackgroundColor,
      ReamColors.dark.paper,
    );
  });

  // --- Task 11: move-to-folder / manage-tags actions ---

  Document doc1() => Document(
    id: 1,
    name: 'Scan 2026-06-27 20.26.42',
    createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
    modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
  );

  testWidgets(
    'moving a document from its menu creates the folder and calls moveToFolder',
    (tester) async {
      final repo = FakeDocumentRepository(documents: [doc1()]);
      await pumpHome(tester, repo);

      await tester.tap(find.byKey(const Key('document-menu-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-move-1')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('move-to-folder-new')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create-folder-field')),
        'Work',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-folder-save')));
      await tester.pumpAndSettle();

      final folders = await repo.listFolders();
      final workId = folders.singleWhere((f) => f.name == 'Work').id;
      await tester.tap(find.byKey(Key('move-to-folder-$workId')));
      await tester.pumpAndSettle();

      expect(folders, hasLength(1));
      final summaries = await repo.listDocumentSummaries();
      expect(summaries.single.folderId, workId);
    },
  );

  testWidgets('a move failure shows an error SnackBar', (tester) async {
    final repo = FakeDocumentRepository(documents: [doc1()], throwOnMove: true);
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-move-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('move-to-folder-unfiled')));
    await tester.pumpAndSettle();

    // moveToFolder throws (throwOnMove) so this actually exercises the
    // _moveDocument catch branch and its error SnackBar.
    expect(find.text("Couldn't move document"), findsOneWidget);
  });

  testWidgets('managing tags from the menu updates document tags', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(documents: [doc1()]);
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-tags-1')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manage-tags-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('create-tag-field')),
      'Important',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('create-tag-save')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('manage-tags-done')));
    await tester.pumpAndSettle();

    final tags = await repo.tagsForDocument(1);
    expect(tags.map((t) => t.name), contains('Important'));
  });

  testWidgets('a tags-update failure shows an error SnackBar', (tester) async {
    final repo = FakeDocumentRepository(
      documents: [doc1()],
      throwOnSetTags: true,
    );
    await pumpHome(tester, repo);
    await repo.createTag('Existing');

    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-tags-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-tags-done')));
    await tester.pumpAndSettle();

    // setDocumentTags throws (throwOnSetTags) so this actually exercises the
    // _manageTags catch branch and its error SnackBar.
    expect(find.text("Couldn't update tags"), findsOneWidget);
  });

  testWidgets('selection bar shows Move/Tag buttons when features are on', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(documents: [doc1()]);
    await pumpHome(tester, repo);

    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selection-move')), findsOneWidget);
    expect(find.byKey(const Key('selection-tag')), findsOneWidget);
  });

  testWidgets('selection bar hides Move/Tag buttons when features are off', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(documents: [doc1()]);
    await pumpHome(
      tester,
      repo,
      features: const FeatureFlags(folders: false, tags: false),
    );

    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('selection-move')), findsNothing);
    expect(find.byKey(const Key('selection-tag')), findsNothing);
  });

  testWidgets('bulk move applies the chosen folder to every selected doc', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      documents: [
        doc1(),
        Document(
          id: 2,
          name: 'Second',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
        ),
      ],
    );
    await pumpHome(tester, repo);

    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-check-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-move')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('move-to-folder-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('create-folder-field')),
      'Bulk',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('create-folder-save')));
    await tester.pumpAndSettle();

    final createdFolders = await repo.listFolders();
    final bulkId = createdFolders.singleWhere((f) => f.name == 'Bulk').id;
    await tester.tap(find.byKey(Key('move-to-folder-$bulkId')));
    await tester.pumpAndSettle();

    final summaries = await repo.listDocumentSummaries();
    expect(summaries.every((s) => s.folderId == bulkId), true);
    // Selection clears after a successful bulk action.
    expect(find.byKey(const Key('selection-bar')), findsNothing);
  });

  testWidgets('a bulk-move failure shows an error SnackBar', (tester) async {
    final repo = FakeDocumentRepository(
      documents: [
        doc1(),
        Document(
          id: 2,
          name: 'Second',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
        ),
      ],
      throwOnMove: true,
    );
    await pumpHome(tester, repo);

    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-check-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-move')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('move-to-folder-unfiled')));
    await tester.pumpAndSettle();

    // moveToFolder throws (throwOnMove) so this exercises the _bulkMove
    // catch branch and its error SnackBar; selection is NOT cleared because
    // the catch path returns before _clearSelection().
    expect(find.text("Couldn't move documents"), findsOneWidget);
    expect(find.byKey(const Key('selection-bar')), findsOneWidget);
  });

  testWidgets('bulk tag sheet starts with nothing pre-selected', (
    tester,
  ) async {
    final repo = FakeDocumentRepository(
      documents: [
        doc1(),
        Document(
          id: 2,
          name: 'Second',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
        ),
      ],
    );
    final common = await repo.createTag('Common');
    await repo.setDocumentTags(1, {common.id});
    await repo.setDocumentTags(2, {common.id});
    await pumpHome(tester, repo);

    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-check-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-tag')));
    await tester.pumpAndSettle();

    // The bulk sheet is for ADDING tags, so nothing starts pre-checked even
    // though both selected docs already carry the "Common" tag.
    final chip = tester.widget<FilterChip>(
      find.byKey(Key('manage-tag-chip-${common.id}')),
    );
    expect(chip.selected, false);
  });

  testWidgets(
    'bulk tag ADDS the chosen tags to every selected doc without dropping '
    "docs' other existing tags (merge, not replace)",
    (tester) async {
      final repo = FakeDocumentRepository(
        documents: [
          doc1(),
          Document(
            id: 2,
            name: 'Second',
            createdAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
            modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
          ),
        ],
      );
      // A={t1,t2}, B={t1,t3} — t1 common, t2/t3 doc-specific.
      final t1 = await repo.createTag('t1');
      final t2 = await repo.createTag('t2');
      final t3 = await repo.createTag('t3');
      await repo.setDocumentTags(1, {t1.id, t2.id});
      await repo.setDocumentTags(2, {t1.id, t3.id});
      await pumpHome(tester, repo);

      await tester.longPress(find.byKey(const Key('document-tile-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('document-check-2')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('selection-tag')));
      await tester.pumpAndSettle();

      // Create + select a new tag t4 to add to both docs.
      await tester.tap(find.byKey(const Key('manage-tags-new')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('create-tag-field')), 't4');
      await tester.pump();
      await tester.tap(find.byKey(const Key('create-tag-save')));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('manage-tags-done')));
      await tester.pumpAndSettle();

      final tags1 = (await repo.tagsForDocument(1)).map((t) => t.name).toSet();
      final tags2 = (await repo.tagsForDocument(2)).map((t) => t.name).toSet();
      // A={t1,t2,t4}, B={t1,t3,t4} — nothing lost, t4 added to both.
      expect(tags1, {'t1', 't2', 't4'});
      expect(tags2, {'t1', 't3', 't4'});
      expect(find.byKey(const Key('selection-bar')), findsNothing);
    },
  );

  testWidgets('a bulk-tag failure shows an error SnackBar', (tester) async {
    final repo = FakeDocumentRepository(
      documents: [
        doc1(),
        Document(
          id: 2,
          name: 'Second',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 43),
        ),
      ],
      throwOnSetTags: true,
    );
    await pumpHome(tester, repo);
    await repo.createTag('Existing');

    await tester.longPress(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-check-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-tag')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('manage-tags-done')));
    await tester.pumpAndSettle();

    // setDocumentTags throws (throwOnSetTags) so this exercises the
    // _bulkTag catch branch and its error SnackBar; selection is NOT
    // cleared because the catch path returns before _clearSelection().
    expect(find.text("Couldn't update tags"), findsOneWidget);
    expect(find.byKey(const Key('selection-bar')), findsOneWidget);
  });
}
