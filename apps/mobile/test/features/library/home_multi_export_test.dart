import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile/features/library/document.dart';
import 'package:mobile/features/library/file_archiver.dart';
import 'package:mobile/features/library/home_screen.dart';
import 'package:mobile/features/library/library_dependencies.dart';

import '../../support/fake_library.dart';

void main() {
  HomeScreen homeWith(
    FakeDocumentRepository repo,
    FakeShareChannel share, {
    FileArchiver? archiver,
  }) =>
      HomeScreen(
        libraryDependencies: LibraryDependencies(
          createRepository: () async => repo,
          share: share,
          archiver: archiver ?? FakeFileArchiver(),
        ),
      );

  Document doc(int id, String name) => Document(
        id: id,
        name: name,
        createdAt: DateTime.utc(2026, 7, 2),
        modifiedAt: DateTime.utc(2026, 7, 2),
      );

  Future<void> enterSelection(WidgetTester tester, int id) async {
    await tester.longPress(find.byKey(Key('document-tile-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('long-press enters selection mode with an N-selected title',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, FakeShareChannel())));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.byKey(const Key('selection-export')), findsOneWidget);

    // Close clears selection and restores the normal app bar.
    await tester.tap(find.byKey(const Key('selection-close')));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('Documents'), findsOneWidget);
  });

  testWidgets('one selected document exports a single PDF and shares it',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.exportedIds, [1]);
    expect(repo.combinedExports, isEmpty);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastSubject, 'A');
    expect(find.text('1 selected'), findsNothing);
  });

  testWidgets('2+ selected + Merge calls exportCombinedPdf then shares',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle(); // choice dialog
    await tester.tap(find.byKey(const Key('export-choice-merged')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.combinedExports, [
      [1, 2] // display order: created desc, tie-break id asc → doc 1 then doc 2
    ]);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('.pdf'));
    expect(share.lastSubject, '2 documents');
  });

  testWidgets('2+ selected + Separate zips the PDFs then shares the zip',
      (tester) async {
    final repo = FakeDocumentRepository(documents: [doc(1, 'A'), doc(2, 'B')]);
    final share = FakeShareChannel();
    final archiver = FakeFileArchiver();
    await tester
        .pumpWidget(MaterialApp(home: homeWith(repo, share, archiver: archiver)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-choice-zip')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.separateExports, [
      [1, 2]
    ]);
    expect(archiver.calls, 1);
    expect(archiver.lastArchiveName, 'documents.zip');
    expect(archiver.lastEntryNames, ['fake-sep-1.pdf', 'fake-sep-2.pdf']);
    expect(share.calls, 1);
    expect(share.lastFilePaths!.single, endsWith('documents.zip'));
  });

  testWidgets('double-tapping Export on one selection runs one export',
      (tester) async {
    final gate = Completer<void>();
    final repo = FakeDocumentRepository(
        documents: [doc(1, 'A')], exportGate: gate);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pump();

    gate.complete();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(repo.exportedIds.length, 1);
    expect(share.calls, 1);
  });

  testWidgets('a failing export shows a share error', (tester) async {
    final repo = FakeDocumentRepository(
        documents: [doc(1, 'A'), doc(2, 'B')], throwOnExport: true);
    final share = FakeShareChannel();
    await tester.pumpWidget(MaterialApp(home: homeWith(repo, share)));
    await tester.pumpAndSettle();

    await enterSelection(tester, 1);
    await tester.tap(find.byKey(const Key('document-tile-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('selection-export')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-choice-merged')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(share.calls, 0);
    expect(find.text("Couldn't share"), findsOneWidget);
  });
}
