import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/home_screen.dart';

import '../../support/fake_library.dart';
import '../../support/fake_scan.dart';

void main() {
  Future<void> pumpHome(WidgetTester tester, FakeDocumentRepository repo) async {
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(repo),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the Documents app bar title', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.widgetWithText(AppBar, 'Documents'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no documents',
      (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.text('No documents yet'), findsOneWidget);
  });

  testWidgets('lists saved documents when storage is non-empty',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [
      Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
    ]);
    await pumpHome(tester, repo);
    expect(find.byKey(const Key('documents-list')), findsOneWidget);
    expect(find.text('Scan 2026-06-27 20.26.42'), findsOneWidget);
    expect(find.text('No documents yet'), findsNothing);
  });

  testWidgets('shows a tappable Scan button once loaded', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    final fab = tester.widget<FloatingActionButton>(
      find.widgetWithText(FloatingActionButton, 'Scan'),
    );
    expect(fab.onPressed, isNotNull);
  });

  testWidgets('tapping Scan opens the camera screen', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    await tester.tap(find.widgetWithText(FloatingActionButton, 'Scan'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Scan'), findsOneWidget);
    expect(find.byKey(const Key('scan-preview')), findsOneWidget);
  });

  testWidgets('shows an error view (not an infinite spinner) when load fails',
      (tester) async {
    await pumpHome(tester, FakeDocumentRepository(throwOnList: true));
    expect(find.byKey(const Key('documents-loading')), findsNothing);
    expect(find.byKey(const Key('documents-error')), findsOneWidget);
    expect(find.byKey(const Key('documents-retry')), findsOneWidget);
  });

  testWidgets('tapping a document opens the page viewer', (tester) async {
    final repo = FakeDocumentRepository(documents: [
      Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
    ]);
    await pumpHome(tester, repo);

    await tester.tap(find.byKey(const Key('document-tile-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('page-viewer-delete')), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Scan 2026-06-27 20.26.42'),
        findsOneWidget);
  });

  testWidgets('renaming from the list menu updates the document name',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [
      Document(
          id: 1,
          name: 'Scan 2026-06-27 20.26.42',
          createdAt: DateTime.utc(2026, 6, 27, 20, 26, 42),
          modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
    ]);
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
            modifiedAt: DateTime.utc(2026, 6, 27, 20, 26, 42)),
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

  // --- D3: sort control ---
  List<Document> twoDocs() => [
        Document(
            id: 1,
            name: 'apple',
            createdAt: DateTime.utc(2026, 1, 1, 10),
            modifiedAt: DateTime.utc(2026, 1, 1, 10)),
        Document(
            id: 2,
            name: 'Zebra',
            createdAt: DateTime.utc(2026, 1, 1, 12), // newer
            modifiedAt: DateTime.utc(2026, 1, 1, 12)),
      ];

  testWidgets('sort control is hidden when the list is empty', (tester) async {
    await pumpHome(tester, FakeDocumentRepository());
    expect(find.byKey(const Key('sort-control-bar')), findsNothing);
  });

  testWidgets('sort control is hidden in the error state', (tester) async {
    await pumpHome(tester, FakeDocumentRepository(throwOnList: true));
    expect(find.byKey(const Key('sort-control-bar')), findsNothing);
    expect(find.byKey(const Key('documents-error')), findsOneWidget);
  });

  testWidgets('sort control is hidden while loading', (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(listGate: gate, documents: twoDocs());
    await tester.pumpWidget(MaterialApp(
      home: HomeScreen(
        dependencies: grantedScanDependencies(),
        libraryDependencies: fakeLibraryDependencies(repo),
      ),
    ));
    await tester.pump(); // let _init start; _load is blocked on the gate
    expect(find.byKey(const Key('documents-loading')), findsOneWidget);
    expect(find.byKey(const Key('sort-control-bar')), findsNothing);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('sort-control-bar')), findsOneWidget);
  });

  testWidgets('sort control is shown when the library is non-empty',
      (tester) async {
    await pumpHome(tester, FakeDocumentRepository(documents: twoDocs()));
    expect(find.byKey(const Key('sort-control-bar')), findsOneWidget);
  });

  testWidgets('default sort is newest-created first', (tester) async {
    await pumpHome(tester, FakeDocumentRepository(documents: twoDocs()));
    // created desc: Zebra (12:00) above apple (10:00).
    final dyZebra = tester.getCenter(find.text('Zebra')).dy;
    final dyApple = tester.getCenter(find.text('apple')).dy;
    expect(dyZebra, lessThan(dyApple));
  });

  testWidgets('tapping the Name chip re-orders the list in place',
      (tester) async {
    final repo = FakeDocumentRepository(documents: twoDocs());
    await pumpHome(tester, repo);
    await tester.tap(find.byKey(const Key('sort-chip-name')));
    await tester.pumpAndSettle();
    // name asc: apple above Zebra (flips the default order).
    final dyApple = tester.getCenter(find.text('apple')).dy;
    final dyZebra = tester.getCenter(find.text('Zebra')).dy;
    expect(dyApple, lessThan(dyZebra));
  });

  testWidgets('renaming under an active Name sort re-positions the document',
      (tester) async {
    final repo = FakeDocumentRepository(documents: twoDocs());
    await pumpHome(tester, repo);
    // Activate Name sort (asc): apple above Zebra.
    await tester.tap(find.byKey(const Key('sort-chip-name')));
    await tester.pumpAndSettle();
    expect(tester.getCenter(find.text('apple')).dy,
        lessThan(tester.getCenter(find.text('Zebra')).dy));
    // Rename 'apple' (id 1) to 'zzz' via its row menu -> under Name asc it must
    // drop below 'Zebra' (z-e-b... < z-z-z). Proves the active sort is
    // preserved across _load() and the renamed doc re-positions.
    await tester.tap(find.byKey(const Key('document-menu-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('document-rename-1')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rename-field')), 'zzz');
    await tester.pump();
    await tester.tap(find.byKey(const Key('rename-save')));
    await tester.pumpAndSettle();
    expect(find.text('apple'), findsNothing);
    expect(tester.getCenter(find.text('Zebra')).dy,
        lessThan(tester.getCenter(find.text('zzz')).dy),
        reason: 'after rename to zzz, Zebra sorts above it under Name asc');
  });

  testWidgets('sorting does not trigger a repository re-query',
      (tester) async {
    final repo = FakeDocumentRepository(documents: twoDocs());
    await pumpHome(tester, repo);
    final callsAfterLoad = repo.listCalls;
    await tester.tap(find.byKey(const Key('sort-chip-name')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sort-chip-name'))); // flip direction
    await tester.pumpAndSettle();
    expect(repo.listCalls, callsAfterLoad,
        reason: 'sorting is in-memory; no listDocumentSummaries re-query');
  });
}
